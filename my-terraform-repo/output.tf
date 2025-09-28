# --- Outputs ---
output "portfolio_alb_dns" {
  value = aws_lb.portfolio_alb.dns_name
}