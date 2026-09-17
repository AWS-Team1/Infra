variable "app_database_password_file" {
  description = "bank_app 비밀번호 파일의 로컬 경로"
  type        = string
  default     = "~/.cache/boa/database/app.password"
}

variable "accounts_database_password_file" {
  description = "accounts_app 비밀번호 파일의 로컬 경로"
  type        = string
  default     = "~/.cache/boa/database/accounts.password"
}

variable "ledger_database_password_file" {
  description = "ledger_app 비밀번호 파일의 로컬 경로"
  type        = string
  default     = "~/.cache/boa/database/ledger.password"
}
