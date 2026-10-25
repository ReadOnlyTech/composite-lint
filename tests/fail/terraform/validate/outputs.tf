output "hello" {
  description = "A greeting"
  # Expected to fail terraform validate: var.nope isn't declared
  value = var.nope
}
