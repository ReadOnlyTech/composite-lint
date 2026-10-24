terraform {
  required_version = ">= 1.0"
}

output "hello" {
  # Expected to fail terraform validate: var.nope isn't declared
  value = var.nope
}
