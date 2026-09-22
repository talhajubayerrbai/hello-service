output "public_ip" {
  value = aws_eip.hello.public_ip
}

output "url" {
  value = "http://${aws_eip.hello.public_ip}"
}
