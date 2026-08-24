class RegistrationDraft {
  String email;
  String fullName;
  String phone;
  bool phoneSkipped;
  String password;
  bool termsAccepted;

  RegistrationDraft({
    this.email = '',
    this.fullName = '',
    this.phone = '',
    this.phoneSkipped = false,
    this.password = '',
    this.termsAccepted = false,
  });

  bool get isStep1Done => email.trim().isNotEmpty && email.contains('@');
  bool get isStep2Done => fullName.trim().length >= 2 && fullName.trim() != 'Sin especificar';
  bool get isStep3Done => phone.trim().isNotEmpty || phoneSkipped;
  bool get isStep4Done => password.length >= 8;
  bool get isAllReadyForSignUp =>
      isStep1Done && isStep2Done && isStep3Done && isStep4Done && termsAccepted;

  void clear() {
    email = '';
    fullName = '';
    phone = '';
    phoneSkipped = false;
    password = '';
    termsAccepted = false;
  }
}
