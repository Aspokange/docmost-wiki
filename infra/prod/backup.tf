# --------- S3 Bucket ---------
resource "aws_s3_bucket" "backup" {
  bucket = "docmost-backups-${var.environment}-682135518833-v2"

  tags = {
    Name        = "Docmost Backup ${var.environment}"
    Environment = var.environment
  }
}

# --------- Versioning ---------
resource "aws_s3_bucket_versioning" "backup_versioning" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# --------- Block Public Access ---------
resource "aws_s3_bucket_public_access_block" "backup_block" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------- Lifecycle Policy ---------
resource "aws_s3_bucket_lifecycle_configuration" "backup_lifecycle" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "backup-retention"
    status = "Enabled"

    filter {}

    # Move to Glacier after 30 days
    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    # Delete after 90 days
    expiration {
      days = 90
    }
  }
}

# --------- IAM Role for EC2 ---------
resource "aws_iam_role" "ec2_role" {
  name = "docmost-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# --------- Instance Profile ---------
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "docmost-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name
}

# --------- Backup Policy ---------
resource "aws_iam_policy" "backup_policy" {
  name = "docmost-backup-policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      }
    ]
  })
}

# --------- Attach Policy to Role ---------
resource "aws_iam_role_policy_attachment" "backup_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.backup_policy.arn
}