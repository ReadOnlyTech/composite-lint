terraform {
  required_version = ">= 1.0"
}

output "hello" {
  # Expected to fail terraform fmt: the next line has no spaces around its equals sign
  value="hello"
}
