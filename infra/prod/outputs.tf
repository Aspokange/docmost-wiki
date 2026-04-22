output "public_ip" {
  value = aws_instance.docmost.public_ip
}

output "instance_id" {
  value = aws_instance.docmost.id
}