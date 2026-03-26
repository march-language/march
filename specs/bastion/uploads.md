# Bastion: Multipart Uploads

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Streaming Multipart Parser

Bastion includes a streaming multipart parser that processes uploads without buffering the entire request body in memory. Large files are streamed to temporary storage as they arrive.

```march
mod Bastion.Upload do
  type UploadedFile = {
    filename: String,         # original filename from the client
    content_type: String,     # MIME type
    path: String,             # path to temporary file on disk
    size: Int                 # file size in bytes
  }

  type UploadOpts = {
    max_file_size: Int,       # max size per file (default: 10MB)
    max_files: Int,           # max number of files (default: 10)
    max_field_size: Int,      # max size for non-file fields (default: 64KB)
    allowed_types: List(String),  # allowed MIME types (default: all)
    temp_dir: String          # temporary storage directory (default: system temp)
  }
end
```

---

## Typed Middleware Integration

Uploads integrate with the typed middleware pipeline. After parsing, the conn carries upload data in a type-safe way:

```march
type WithUpload = { uploads: Map(String, UploadedFile), fields: Map(String, String) }

mod Bastion.Middleware.Upload do
  # Parse multipart form data — streams files to temp storage
  fn parse_multipart(conn: Conn(Parsed), opts: UploadOpts) -> Result(Conn(Parsed & WithUpload), UploadError)
end

type UploadError =
  | FileTooLarge(String, Int)       # filename, actual size
  | TooManyFiles(Int)                # actual count
  | DisallowedType(String, String)   # filename, content_type
  | MalformedMultipart(String)       # error description
```

---

## Usage in Handlers

```march
fn route(conn, :post, ["photos", "upload"]) do
  case Bastion.Middleware.Upload.parse_multipart(conn, %{
    max_file_size: 5_000_000,       # 5MB per photo
    max_files: 10,
    allowed_types: ["image/jpeg", "image/png", "image/webp"]
  }) do
    Ok(conn) ->
      uploads = conn.assigns.uploads
      caption = conn.assigns.fields["caption"] |> Option.unwrap("")

      # Process each uploaded file
      results = uploads
      |> Map.values()
      |> List.map(fn upload ->
        # Move from temp to permanent storage
        dest = "priv/uploads/photos/#{generate_id()}_#{upload.filename}"
        File.rename(upload.path, dest)
        MyApp.Photos.create(conn.assigns.db, %{
          path: dest,
          caption: caption,
          content_type: upload.content_type,
          size: upload.size
        })
      end)

      conn |> json(%{uploaded: List.length(results)})

    Error(FileTooLarge(name, size)) ->
      conn |> json(%{error: "File '#{name}' is too large (#{size} bytes)"}, status: 413)

    Error(DisallowedType(name, type)) ->
      conn |> json(%{error: "File type '#{type}' is not allowed for '#{name}'"}, status: 422)

    Error(err) ->
      conn |> json(%{error: "Upload failed: #{inspect(err)}"}, status: 400)
  end
end
```

---

## Streaming to External Storage

For production deployments, files can be streamed directly to object storage (S3, GCS, etc.) without touching disk:

```march
fn route(conn, :post, ["files", "upload"]) do
  Bastion.Upload.stream_to(conn, %{
    max_file_size: 100_000_000,  # 100MB
    on_file: fn filename, content_type, stream ->
      # Stream chunks directly to S3 as they arrive
      MyApp.S3.upload_stream("my-bucket", "uploads/#{filename}", stream, %{
        content_type: content_type
      })
    end,
    on_field: fn name, value ->
      # Collect non-file form fields
      %{name => value}
    end
  })
end
```

---

## Cleanup

Temporary files are automatically cleaned up after the request completes, whether the handler succeeds or fails. Bastion registers an after-response callback that deletes any temp files created during multipart parsing.

The request size limit (see [security.md](security.md)) applies to upload routes too. Override it per-route for upload endpoints:

```march
fn route(conn, :post, ["uploads"]) do
  conn
  |> Bastion.Middleware.max_body_size(50_000_000)   # 50MB for uploads
  |> handle_upload()
end
```
