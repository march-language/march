; Indent after 'do' keyword (covers fn, mod, actor, match, block bodies)
(_ "do" @indent)

; Indent after 'then' and 'else' in if expressions
(_ "then" @indent)
(_ "else" @indent)

; Indent after '->' in match arms and lambdas
(match_arm "->" @indent)
(lambda_expression "->" @indent)

; Outdent on 'end'
(_ "end" @outdent)

; Outdent on closing brackets
(_ ")" @outdent)
(_ "]" @outdent)
(_ "}" @outdent)
