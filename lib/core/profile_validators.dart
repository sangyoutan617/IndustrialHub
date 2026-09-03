class ProfileValidators {
  const ProfileValidators._();

  static const int maxNameLength = 40;
  static const int maxJobTitleLength = 30;
  static const int maxCompanyLength = 30;
  static const int minPhoneLength = 10;
  static const int maxPhoneLength = 13;

  static String? validateName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Name is required';
    if (trimmed.length > maxNameLength) {
      return 'Must be $maxNameLength characters or fewer';
    }
    return null;
  }

  static String? validateJobTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length > maxJobTitleLength) {
      return 'Must be $maxJobTitleLength characters or fewer';
    }
    return null;
  }

  static String? validateCompany(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length > maxCompanyLength) {
      return 'Must be $maxCompanyLength characters or fewer';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length < minPhoneLength || trimmed.length > maxPhoneLength) {
      return 'Must be $minPhoneLength to $maxPhoneLength characters';
    }
    return null;
  }
}
