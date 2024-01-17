## Please, Configure you project settings on variable.tf file.

#### To reproduce the error, apply the resources. Edit some information in the backend service, for example:

```
custom_request_headers = [
  "host:${google_storage_bucket.storage_website.name}",
  "cookie:",
]
```

to

```
custom_request_headers = [
  "host:${google_storage_bucket.storage_website.name}",
  "cookie:123",
]
```

Execute the plan and try to apply it; the error googleapi: Error 400: Invalid value for field 'resource.securitySettings' will occur.