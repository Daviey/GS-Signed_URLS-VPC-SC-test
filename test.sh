#!/bin/bash

set -eo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

print_colored() { echo -e "${1}${2}${NC}"; }
pause() { read -n 1 -s -r -p "Press any key to continue..."; echo; }

run_terraform() {
  if ! terraform "$@"; then
    print_colored "$RED" "Terraform command failed: terraform $*"
    exit 1
  fi
}

get_terraform_output() {
  local output_value
  output_value=$(terraform output -raw "$1" 2>/dev/null)
  
  if [ $? -ne 0 ] || [ -z "$output_value" ]; then
    print_colored "$RED" "Failed to get Terraform output for $1"
    return 1
  fi
  
  echo "$output_value"
}

test_access() {
  local test_type=$1
  local command=$2
  local expected_failure=$3

  print_colored "$YELLOW" "Testing $test_type:"
  echo "+ $command"
  output=$(eval "$command")
  exit_code=$?
  echo "$output"
  
  if [ $exit_code -eq 0 ]; then
    if [ "$expected_failure" = true ]; then
      print_colored "$RED" "Access is unexpected"
    else
      print_colored "$GREEN" "Access is as expected"
    fi
  else
    if [ "$expected_failure" = true ]; then
      print_colored "$GREEN" "Access is as expected"
    else
      print_colored "$RED" "Access is unexpected"
    fi
  fi
  pause
}

main() {
  print_colored "$GREEN" "Deploying infrastructure without VPC-SC..."
  run_terraform apply -var="enable_vpc_sc=false" -auto-approve

  pre_vpc_sc_signed_url=$(get_terraform_output pre_vpc_sc_signed_url)
  additional_pre_vpc_sc_signed_url=$(get_terraform_output additional_pre_vpc_sc_signed_url)
  bucket_name=$(get_terraform_output bucket_name)

  print_colored "$GREEN" "Testing access before enabling VPC-SC:"
  test_access "pre-VPC-SC signed URL access" "curl -s \"$pre_vpc_sc_signed_url\"" false
  test_access "additional pre-VPC-SC signed URL access (with custom header)" "curl -s -H 'x-goog-custom-header: custom_value' \"$additional_pre_vpc_sc_signed_url\"" false
  test_access "additional pre-VPC-SC signed URL access (without custom header)" "curl -s \"$additional_pre_vpc_sc_signed_url\"" false
  test_access "direct gsutil access" "gsutil cat gs://$bucket_name/sample.txt" false
  test_access "direct gcloud access" "gcloud storage ls gs://$bucket_name" false
  test_access "content-type verification" "curl -s -I \"$pre_vpc_sc_signed_url\" | grep -i 'Content-Type: text/plain'" false

  print_colored "$GREEN" "Enabling VPC-SC..."
  run_terraform apply -var="enable_vpc_sc=true" -auto-approve

  print_colored "$GREEN" "Waiting for VPC-SC changes to propagate..."
  sleep 30s

  post_vpc_sc_signed_url=$(get_terraform_output post_vpc_sc_signed_url)

  print_colored "$GREEN" "Testing access after enabling VPC-SC:"
  test_access "pre-VPC-SC signed URL access" "curl -s \"$pre_vpc_sc_signed_url\"" false
  test_access "additional pre-VPC-SC signed URL access (with custom header)" "curl -s -H 'x-goog-custom-header: custom_value' \"$additional_pre_vpc_sc_signed_url\"" false
  test_access "post-VPC-SC signed URL access (with custom header)" "curl -s -H 'x-goog-custom-header: custom_value' \"$post_vpc_sc_signed_url\"" false
  test_access "post-VPC-SC signed URL access (without custom header)" "curl -s \"$post_vpc_sc_signed_url\"" false
  test_access "direct gsutil access" "gsutil cat gs://$bucket_name/sample.txt" true
  test_access "direct gcloud access" "gcloud storage ls gs://$bucket_name" false
  test_access "content-type verification" "curl -s -I -H 'x-goog-custom-header: custom_value' \"$post_vpc_sc_signed_url\" | grep -i 'Content-Type: text/plain'" false

  print_colored "$GREEN" "VPC-SC test completed."
}

main
