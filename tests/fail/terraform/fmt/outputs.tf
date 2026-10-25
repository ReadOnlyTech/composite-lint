output "hello" {
  description = "A greeting"
  # Expected to fail terraform fmt: the next line has no spaces around its equals sign
  value="hello"
}
