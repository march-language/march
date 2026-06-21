//! Proc-macros for the March Rust FFI layer.
//!
//!   * `#[march]`           — generate the `#[no_mangle] extern "C"` shim for a fn.
//!   * `#[derive(Encoder)]` — `ToMarch` for a struct/enum ↔ March record/variant.
//!   * `#[derive(Decoder)]` — `FromMarch`.
//!   * `init!("lib", [..])` — emit the binding manifest (the March extern block).
//!
//! Representation rules mirror the C ABI: top-level args/returns and record/
//! variant fields use the *native slot* form (`Int`/`Bool` raw); `Result`/
//! `Option` payloads use the *tagged* form. The runtime traits encode both.

use proc_macro::TokenStream;
use quote::{format_ident, quote};
use syn::{parse_macro_input, Data, DeriveInput, Fields, FnArg, ItemFn, Pat, ReturnType, Type};

// ── type classification ─────────────────────────────────────────────────────

fn type_last_ident(ty: &Type) -> Option<String> {
    if let Type::Path(p) = ty {
        p.path.segments.last().map(|s| s.ident.to_string())
    } else {
        None
    }
}

fn is_f64(ty: &Type) -> bool {
    type_last_ident(ty).as_deref() == Some("f64")
}

fn is_result(ty: &Type) -> bool {
    type_last_ident(ty).as_deref() == Some("Result")
}

fn is_str_ref(ty: &Type) -> bool {
    matches!(ty, Type::Reference(r) if type_last_ident(&r.elem).as_deref() == Some("str"))
}

fn is_bytes_ref(ty: &Type) -> bool {
    matches!(ty, Type::Reference(r) if matches!(&*r.elem, Type::Slice(_)))
}

/// March type name for a Rust type (best-effort, for the generated extern block).
fn march_type_name(ty: &Type) -> String {
    if is_str_ref(ty) {
        return "String".into();
    }
    if is_bytes_ref(ty) {
        return "Bytes".into();
    }
    match type_last_ident(ty).as_deref() {
        Some("i64") | Some("i32") | Some("u32") | Some("usize") => "Int".into(),
        Some("f64") => "Float".into(),
        Some("bool") => "Bool".into(),
        Some("String") => "String".into(),
        Some("Error") => "String".into(), // march::Error encodes to a March String
        Some("Vec") => "Bytes".into(),
        Some("Result") => result_march_name(ty),
        Some("Option") => option_march_name(ty),
        Some("ResourceArc") => generic_args(ty)
            .get(0)
            .and_then(type_last_ident)
            .unwrap_or_else(|| "Resource".into()), // opaque resource type name
        Some(other) => other.into(), // a derived record/variant type
        None => "Int".into(),
    }
}

fn generic_args(ty: &Type) -> Vec<Type> {
    if let Type::Path(p) = ty {
        if let Some(seg) = p.path.segments.last() {
            if let syn::PathArguments::AngleBracketed(a) = &seg.arguments {
                return a
                    .args
                    .iter()
                    .filter_map(|g| match g {
                        syn::GenericArgument::Type(t) => Some(t.clone()),
                        _ => None,
                    })
                    .collect();
            }
        }
    }
    vec![]
}

fn result_march_name(ty: &Type) -> String {
    let args = generic_args(ty);
    let ok = args.get(0).map(march_type_name).unwrap_or_else(|| "Int".into());
    let err = args.get(1).map(march_type_name).unwrap_or_else(|| "String".into());
    format!("Result({}, {})", ok, err)
}

fn option_march_name(ty: &Type) -> String {
    let args = generic_args(ty);
    let inner = args.get(0).map(march_type_name).unwrap_or_else(|| "Int".into());
    format!("Option({})", inner)
}

// ── #[march] ────────────────────────────────────────────────────────────────

#[proc_macro_attribute]
pub fn march(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let func = parse_macro_input!(item as ItemFn);
    let name = func.sig.ident.clone();
    let impl_name = format_ident!("__march_impl_{}", name);

    // Parameters: C signature + decode expressions + March param signature.
    let mut c_params = Vec::new();
    let mut decode_exprs = Vec::new();
    let mut march_params = Vec::new();
    for arg in func.sig.inputs.iter() {
        let FnArg::Typed(pt) = arg else {
            return syn::Error::new_spanned(arg, "#[march] does not support `self`")
                .to_compile_error()
                .into();
        };
        let Pat::Ident(pi) = &*pt.pat else {
            return syn::Error::new_spanned(&pt.pat, "#[march] needs a simple parameter name")
                .to_compile_error()
                .into();
        };
        let pname = pi.ident.clone();
        let ty = &*pt.ty;
        let (cty, decode) = if is_f64(ty) {
            (quote!(f64), quote!(#pname))
        } else if is_str_ref(ty) {
            (quote!(::march::march_value), quote!(unsafe { ::march::borrow_str(#pname) }))
        } else if is_bytes_ref(ty) {
            (quote!(::march::march_value), quote!(unsafe { ::march::borrow_bytes(#pname) }))
        } else {
            (
                quote!(::march::march_value),
                quote!(<#ty as ::march::FromMarch>::from_march_slot(#pname)),
            )
        };
        c_params.push(quote!(#pname: #cty));
        decode_exprs.push(decode);
        // owned String/Vec ⇒ `consume` on the March side; borrows stay default.
        let consume = matches!(type_last_ident(ty).as_deref(), Some("String") | Some("Vec"));
        let mname = march_type_name(ty);
        march_params.push(if consume {
            format!("consume {}: {}", pname, mname)
        } else {
            format!("{}: {}", pname, mname)
        });
    }

    // Return: C return type, encode of the body result, panic handling.
    let (ret_ty, march_ret): (Option<Type>, String) = match &func.sig.output {
        ReturnType::Default => (None, "Unit".into()),
        ReturnType::Type(_, t) => (Some((**t).clone()), march_type_name(t)),
    };

    let (cret, encode_ok, panic_arm) = match &ret_ty {
        None => (quote!(()), quote!(let _ = __v;), quote!({ ::march::__abort_panic(__p); })),
        Some(t) if is_f64(t) => (
            quote!(f64),
            quote!(return __v;),
            quote!({ ::march::__abort_panic(__p); }),
        ),
        Some(t) if is_result(t) => (
            quote!(::march::march_value),
            quote!(return ::march::ToMarch::to_march(__v);),
            // panic → Err(message) through the same march_value channel.
            quote!({ return ::march::__panic_to_err(__p); }),
        ),
        Some(t) => {
            let _ = t;
            (
                quote!(::march::march_value),
                quote!(return ::march::ToMarch::to_march_slot(__v);),
                quote!({ ::march::__abort_panic(__p); }),
            )
        }
    };

    // Store the generated March extern signature so init! can assemble the block.
    let sig_const = format_ident!("__march_sig_{}", name);
    let march_sig = format!(
        "fn {}({}): {} = \"{}\"",
        name,
        march_params.join(", "),
        march_ret,
        name
    );

    let call = quote!( #impl_name( #(#decode_exprs),* ) );
    let vis = &func.vis;
    let inner = ItemFn {
        vis: syn::Visibility::Inherited,
        sig: syn::Signature { ident: impl_name.clone(), ..func.sig.clone() },
        ..func.clone()
    };

    let expanded = quote! {
        #inner

        #[doc(hidden)]
        #[allow(non_upper_case_globals)]
        #vis const #sig_const: &str = #march_sig;

        #[no_mangle]
        pub extern "C" fn #name( #(#c_params),* ) -> #cret {
            let __r = ::std::panic::catch_unwind(::std::panic::AssertUnwindSafe(|| {
                #call
            }));
            match __r {
                Ok(__v) => { #encode_ok }
                Err(__p) => #panic_arm
            }
        }
    };
    expanded.into()
}

// ── #[derive(Encoder)] / #[derive(Decoder)] ─────────────────────────────────

fn field_kind_char(ty: &Type) -> char {
    match type_last_ident(ty).as_deref() {
        Some("i64") | Some("i32") | Some("bool") | Some("u32") | Some("usize") => 'i',
        Some("f64") => 'f',
        _ => 'p',
    }
}

#[proc_macro_derive(Encoder)]
pub fn derive_encoder(item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as DeriveInput);
    let name = input.ident.clone();
    let body = match &input.data {
        Data::Struct(s) => encode_struct(s),
        Data::Enum(e) => encode_enum(&name, e),
        Data::Union(_) => {
            return syn::Error::new_spanned(&name, "Encoder cannot derive on a union")
                .to_compile_error()
                .into()
        }
    };
    quote! {
        impl ::march::ToMarch for #name {
            fn to_march(self) -> ::march::march_value { #body }
        }
    }
    .into()
}

#[proc_macro_derive(Decoder)]
pub fn derive_decoder(item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as DeriveInput);
    let name = input.ident.clone();
    let body = match &input.data {
        Data::Struct(s) => decode_struct(&name, s),
        Data::Enum(e) => decode_enum(&name, e),
        Data::Union(_) => {
            return syn::Error::new_spanned(&name, "Decoder cannot derive on a union")
                .to_compile_error()
                .into()
        }
    };
    quote! {
        impl ::march::FromMarch for #name {
            fn from_march(v: ::march::march_value) -> Self { #body }
        }
    }
    .into()
}

/// Named record fields sorted by name (March's record layout), with descriptor.
fn sorted_named_fields(fields: &Fields) -> (Vec<syn::Ident>, Vec<Type>, String) {
    let mut named: Vec<(String, syn::Ident, Type)> = Vec::new();
    if let Fields::Named(fs) = fields {
        for f in &fs.named {
            let id = f.ident.clone().unwrap();
            named.push((id.to_string(), id, f.ty.clone()));
        }
    }
    named.sort_by(|a, b| a.0.cmp(&b.0));
    let mut desc = String::new();
    for (n, _, t) in &named {
        desc.push_str(n);
        desc.push(':');
        desc.push(field_kind_char(t));
        desc.push(';');
    }
    desc.push('\0'); // NUL-terminate for march_make_record(const char*)
    (
        named.iter().map(|(_, i, _)| i.clone()).collect(),
        named.iter().map(|(_, _, t)| t.clone()).collect(),
        desc,
    )
}

fn encode_struct(s: &syn::DataStruct) -> proc_macro2::TokenStream {
    let (idents, _tys, desc) = sorted_named_fields(&s.fields);
    let n = idents.len() as i32;
    let desc_bytes = syn::LitByteStr::new(desc.as_bytes(), proc_macro2::Span::call_site());
    let stores = idents.iter().map(|id| quote!(::march::ToMarch::to_march_slot(self.#id)));
    quote! {
        let __fields: [::march::march_value; #n as usize] = [ #(#stores),* ];
        unsafe {
            ::march::sys::march_make_record(
                #desc_bytes.as_ptr() as *const ::core::ffi::c_char,
                #n, __fields.as_ptr())
        }
    }
}

fn decode_struct(name: &syn::Ident, s: &syn::DataStruct) -> proc_macro2::TokenStream {
    let (idents, tys, _desc) = sorted_named_fields(&s.fields);
    let inits = idents.iter().zip(tys.iter()).enumerate().map(|(i, (id, ty))| {
        let i = i as i32;
        quote!(#id: <#ty as ::march::FromMarch>::from_march_slot(
            unsafe { ::march::sys::march_record_field(v, #i) }))
    });
    quote! { #name { #(#inits),* } }
}

fn variant_field_types(fields: &Fields) -> Vec<Type> {
    match fields {
        Fields::Named(fs) => fs.named.iter().map(|f| f.ty.clone()).collect(),
        Fields::Unnamed(fs) => fs.unnamed.iter().map(|f| f.ty.clone()).collect(),
        Fields::Unit => vec![],
    }
}

fn encode_enum(name: &syn::Ident, e: &syn::DataEnum) -> proc_macro2::TokenStream {
    let arms = e.variants.iter().enumerate().map(|(tag, var)| {
        let tag = tag as i32;
        let vname = &var.ident;
        let tys = variant_field_types(&var.fields);
        let n = tys.len() as i32;
        match &var.fields {
            Fields::Unit => quote! {
                #name::#vname => unsafe {
                    ::march::sys::march_make_variant(#tag, 0, ::core::ptr::null())
                }
            },
            Fields::Unnamed(_) => {
                let binds: Vec<syn::Ident> =
                    (0..tys.len()).map(|i| format_ident!("f{}", i)).collect();
                let stores = binds.iter().map(|b| quote!(::march::ToMarch::to_march_slot(#b)));
                quote! {
                    #name::#vname( #(#binds),* ) => {
                        let __fields: [::march::march_value; #n as usize] = [ #(#stores),* ];
                        unsafe { ::march::sys::march_make_variant(#tag, #n, __fields.as_ptr()) }
                    }
                }
            }
            Fields::Named(fs) => {
                let names: Vec<syn::Ident> =
                    fs.named.iter().map(|f| f.ident.clone().unwrap()).collect();
                let stores = names.iter().map(|nm| quote!(::march::ToMarch::to_march_slot(#nm)));
                quote! {
                    #name::#vname { #(#names),* } => {
                        let __fields: [::march::march_value; #n as usize] = [ #(#stores),* ];
                        unsafe { ::march::sys::march_make_variant(#tag, #n, __fields.as_ptr()) }
                    }
                }
            }
        }
    });
    quote! { match self { #(#arms),* } }
}

fn decode_enum(name: &syn::Ident, e: &syn::DataEnum) -> proc_macro2::TokenStream {
    let arms = e.variants.iter().enumerate().map(|(tag, var)| {
        let tag = tag as i32;
        let vname = &var.ident;
        let tys = variant_field_types(&var.fields);
        match &var.fields {
            Fields::Unit => quote! { #tag => #name::#vname },
            Fields::Unnamed(_) => {
                let reads = tys.iter().enumerate().map(|(i, ty)| {
                    let i = i as i32;
                    quote!(<#ty as ::march::FromMarch>::from_march_slot(
                        unsafe { ::march::sys::march_variant_field(v, #i) }))
                });
                quote! { #tag => #name::#vname( #(#reads),* ) }
            }
            Fields::Named(fs) => {
                let reads = fs.named.iter().enumerate().map(|(i, f)| {
                    let id = f.ident.clone().unwrap();
                    let ty = &f.ty;
                    let i = i as i32;
                    quote!(#id: <#ty as ::march::FromMarch>::from_march_slot(
                        unsafe { ::march::sys::march_variant_field(v, #i) }))
                });
                quote! { #tag => #name::#vname { #(#reads),* } }
            }
        }
    });
    quote! {
        match unsafe { ::march::sys::march_variant_tag(v) } {
            #(#arms,)*
            _ => unsafe { ::march::__bad_variant_tag() },
        }
    }
}

// ── init! ───────────────────────────────────────────────────────────────────

struct InitArgs {
    lib: syn::LitStr,
    fns: Vec<syn::Ident>,
}

impl syn::parse::Parse for InitArgs {
    fn parse(input: syn::parse::ParseStream) -> syn::Result<Self> {
        let lib: syn::LitStr = input.parse()?;
        let _: syn::Token![,] = input.parse()?;
        let content;
        syn::bracketed!(content in input);
        let fns = content
            .parse_terminated(syn::Ident::parse, syn::Token![,])?
            .into_iter()
            .collect();
        Ok(InitArgs { lib, fns })
    }
}

#[proc_macro]
pub fn init(item: TokenStream) -> TokenStream {
    let InitArgs { lib, fns } = parse_macro_input!(item as InitArgs);
    let sig_consts: Vec<syn::Ident> =
        fns.iter().map(|f| format_ident!("__march_sig_{}", f)).collect();
    let lib_str = lib.value();
    let header = format!("extern \"{}\" : Cap(Ffi) do", lib_str);
    quote! {
        /// Assemble the March `extern` block for this binding (used by
        /// `forge add-rust` to generate the March side).
        pub fn __march_extern_block() -> ::std::string::String {
            let mut __s = ::std::string::String::from(#header);
            __s.push('\n');
            #( __s.push_str("  "); __s.push_str(#sig_consts); __s.push('\n'); )*
            __s.push_str("end\n");
            __s
        }
        /// Print the generated extern block to stdout (a tiny `main` can call this).
        pub fn march_print_extern_block() {
            print!("{}", __march_extern_block());
        }
    }
    .into()
}
