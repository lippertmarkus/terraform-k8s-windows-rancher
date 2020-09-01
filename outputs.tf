output "rancher_url" {
    value = rancher2_bootstrap.bootstrap.url
}

output "rancher_admin_user" {
    value = rancher2_bootstrap.bootstrap.user
}

output "rancher_admin_password" {
    value = rancher2_bootstrap.bootstrap.current_password
}