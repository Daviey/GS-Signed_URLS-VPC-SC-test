# Google Storage Signed URLS - VPC Service Controls Testing

This project testing for Google Cloud Platform's VPC Service Controls (VPC-SC) using Terraform and Bash scripting.

**TL;DR: It works as expected!**

You can see a sample report in the [sample_report.html](https://html-preview.github.io/?url=https://github.com/Daviey/GS-Signed_URLS-VPC-SC-test/blob/main/sample_report.html) file.

## What's Being Tested

This suite checks:

- Pre-VPC-SC tests:
  - Can we access stuff with a regular signed URL? (Should work)
  - A signed URL with a custom header? (Should also work)
  - Missing the custom header? (Should fail!)
  - `gsutil` access (Should be fine)
  - Using `gcloud storage ls` (Should work)
  - Making sure the content type is what we expect (text/plain in this case)

Sleep for 30 seconds to allow the VPC-SC lockdown to take effect.

- Post-VPC-SC lockdown (which should all be blocked):
  - Trying that pre-VPC-SC signed URL again
  - The custom header URL from before
  - A fresh post-VPC-SC signed URL with the right header
  - Same URL without the header
  - gsutil access
  - gcloud listing
  - Checking the content type again

## Prerequisites

- Terraform 1.0+
- Google Cloud SDK
- Bash shell

## Setup

1. Clone this repository
2. Set up your GCP credentials
3. Update `terraform.tfvars` with your project-specific information

## Usage

To run the full test suite:

```bash
./test.sh
