output "public_ip" {
  value = aws_eip.pacs.public_ip
}

output "ohif_url" {
  value = "http://${aws_eip.pacs.public_ip}/"
}

output "orthanc_explorer_url" {
  value = "http://${aws_eip.pacs.public_ip}/orthanc/ui/app/"
}

output "instance_id" {
  value = aws_instance.pacs.id
}

output "ssm_session_command" {
  value = "aws ssm start-session --region ${var.region} --target ${aws_instance.pacs.id}"
}
