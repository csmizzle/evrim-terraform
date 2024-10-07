// Evrim Dev Bucket for S3
resource "aws_s3_bucket" "evrim-dev-bucket" {
  bucket = "evrim-dev-bucket"

  tags = {
    Name = "Evrim Dev Bucket"
  }
}