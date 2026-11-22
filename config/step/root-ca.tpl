{
  "subject": {{ toJson .Subject }},
  "issuer": {{ toJson .Subject }},
  "keyUsage": ["certSign", "crlSign"],
  "basicConstraints": {"isCA": true, "maxPathLen": 0},
  "nameConstraints": {"critical": true, "permittedDNSDomains": [{{ toJson .Insecure.User.domain }}]}
}
