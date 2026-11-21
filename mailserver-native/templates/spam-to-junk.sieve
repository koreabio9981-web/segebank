require ["fileinto"];
# Rspamd 가 스팸으로 판정한 메일은 Junk(스팸함) 폴더로
if header :is "X-Spam" "Yes" {
  fileinto "Junk";
  stop;
}
