/// One numbered block of the Terms & Conditions / Privacy Policy.
///
/// Every legal document is a title, a "last updated" line, a list of sections
/// and a contact block, so both documents share this shape and the reader
/// screen renders them identically.
class LegalSection {
  /// Section number as shown to the user, e.g. '1'.
  final String number;

  /// Section heading as shown to the user.
  final String heading;

  /// Body copy, one entry per paragraph.
  final List<String> paragraphs;

  const LegalSection({
    required this.number,
    required this.heading,
    required this.paragraphs,
  });
}

/// A complete legal document ready to be rendered by the reader screen.
class LegalDocument {
  final String title;

  /// Rendered under the title, e.g. 'Last updated: 1 October 2026'.
  final String lastUpdated;

  /// Short line under the date explaining that this is the version in force.
  final String intro;

  final List<LegalSection> sections;

  /// Heading of the closing contact block.
  final String contactHeading;

  /// Contact block lines (support email, phone, postal address).
  final List<String> contact;

  const LegalDocument({
    required this.title,
    required this.lastUpdated,
    required this.intro,
    required this.sections,
    required this.contactHeading,
    required this.contact,
  });
}

/// The app's legal copy.
///
/// Kept in one place so the wording can be corrected or replaced by counsel
/// without touching any screen: both documents are rendered by the same
/// `LegalDocumentScreen`, and the Create Account consent checkbox links
/// straight to the relevant one.
class LegalContent {
  LegalContent._();

  static const String supportEmail = 'info@nexzware.com';
  static const String supportPhone = '+91 9791070214';
  static const String supportHours =
      'Support hours: Monday to Saturday, 9:00 AM to 8:00 PM IST.';

  // ------------------------------------------------------------------
  // Terms & Conditions
  // ------------------------------------------------------------------
  static const LegalDocument terms = LegalDocument(
    title: 'ParkShare Terms & Conditions',
    lastUpdated: 'Last updated: 1 October 2026',
    intro:
        'These Terms & Conditions form a binding agreement between you and '
        'ParkShare. By creating an account, listing a parking space, or making '
        'a booking through the ParkShare app, you confirm that you have read, '
        'understood and agreed to everything set out below.',
    sections: [
      LegalSection(
        number: '1',
        heading: 'Acceptance of the Terms',
        paragraphs: [
          'ParkShare operates a platform that connects vehicle owners who '
              'need parking with property owners who have parking space to '
              'rent out. These Terms govern your use of the ParkShare app, '
              'websites and services.',
          'If you do not agree with any part of these Terms, you must not '
              'create an account or use the platform. We may update these '
              'Terms from time to time; the version in force is always the one '
              'published in the app.',
          'These Terms apply equally to parking owners and to vehicle users. '
              'Where a clause is specific to one role, it says so '
              'explicitly.',
        ],
      ),
      LegalSection(
        number: '2',
        heading: 'Eligibility and Account Registration',
        paragraphs: [
          'You must be at least 18 years old and legally able to enter into a '
              'binding contract in your jurisdiction.',
          'You must provide accurate, current and complete registration '
              'details: full name, mobile number, email address and, where '
              'applicable, your UPI ID. You are responsible for keeping these '
              'details accurate.',
          'One person or entity may hold only one ParkShare account. Creating '
              'additional accounts to hold more listings, to influence '
              'availability or to circumvent a limit is a breach of these '
              'Terms.',
          'You are responsible for everything done through your account. Tell '
              'us immediately if you believe your account has been accessed '
              'without your permission, and keep your login credentials '
              'confidential.',
        ],
      ),
      LegalSection(
        number: '3',
        heading: 'Your Role on ParkShare',
        paragraphs: [
          'Parking owners list a parking space they own or are legally '
              'authorised to rent out, set a rent, define the access hours and '
              'the number of vehicles that can be accommodated, and confirm '
              'bookings.',
          'Vehicle users search for a parking space, book it for a period of '
              'time and pay the rent shown at the time of booking.',
          'ParkShare provides the platform, the listing, the booking and the '
              'payment records. ParkShare is not a party to the rental '
              'arrangement between an owner and a user; our role is to record '
              'it accurately and to make the process transparent for both '
              'sides.',
        ],
      ),
      LegalSection(
        number: '4',
        heading: 'Parking Listings and Accuracy of Information',
        paragraphs: [
          'As a parking owner you are solely responsible for the accuracy of '
              'your listing: the address and coordinates, the plot and gate '
              'dimensions, the number of car and bike spaces, the amenities, '
              'the access hours, the rent and the photographs.',
          'You must own the space or have the owner\'s written permission to '
              'rent it out. You may not list a space that is subject to an '
              'active ban, is a designated no-parking zone, or is being used '
              'for an activity that these Terms prohibit.',
          'Listings must not be misleading. Photographs must show the actual '
              'space you are offering, and dimensions must be real '
              'measurements. Nothing is measured from the reference '
              'illustrations shown in the app.',
          'We may ask you to update, re-photograph or remove any listing that '
              'is inaccurate, that misrepresents the space, or that repeatedly '
              'fails to receive the reviews users leave after a visit.',
        ],
      ),
      LegalSection(
        number: '5',
        heading: 'Bookings, Confirmation and Allocation of Space',
        paragraphs: [
          'A booking request is not a confirmed booking. The parking owner '
              'must accept the request (or the listing must have auto-approval '
              'enabled), after which the booking becomes confirmed and a '
              'specific space code is allocated to you.',
          'Only a confirmed booking holds a space. A booking that is still '
              'awaiting owner acceptance, or whose cash payment has not been '
              'collected, does not reserve the space and does not prevent '
              'another vehicle user from booking it.',
          'Owners must respond to booking requests promptly and must not '
              'accept a booking and then refuse entry. Cancelling or refusing '
              'a booking after accepting it may result in the listing being '
              'paused.',
          'A user must display the booking reference on the vehicle and must '
              'park only in the space allocated to that booking.',
        ],
      ),
      LegalSection(
        number: '6',
        heading: 'Rent, Fees and Payment',
        paragraphs: [
          'The rent for a booking is the amount shown in the app at the moment '
              'the booking is made. Owners may not subsequently demand a '
              'higher amount for the same booking.',
          'The platform fee, if any, is shown to you before you confirm the '
              'booking. Any applicable taxes are added or shown separately as '
              'required by law.',
          'Vehicle users may pay online through our payment partner or by '
              'Cash on Delivery. With Cash on Delivery the amount is due to '
              'the parking owner when the vehicle is parked. Until the owner '
              'confirms receipt in the app, the booking stays in COD Pending '
              'and the amount is not counted as owner earnings.',
          'Parking owners must confirm cash receipts in the app. A booking is '
              'not treated as paid, and no earnings are recorded, until they '
              'do so.',
          'We never store your full card or UPI credentials. Payments are '
              'processed by our payment partners under their own terms, and we '
              'keep only the transaction references needed to administer your '
              'booking.',
        ],
      ),
      LegalSection(
        number: '7',
        heading: 'Cancellations, Refunds and Non-Refundable Amounts',
        paragraphs: [
          'Cancellation terms are set by the parking owner in the listing and '
              'are shown before you confirm a booking. Always read them before '
              'paying.',
          'Where a booking is cancelled, any amount that has been paid is '
              'refunded to the original payment method unless the listing '
              'states that the amount is non-refundable.',
          'A Cash on Delivery booking that has not been cancelled remains the '
              'user\'s liability until the amount is collected by the owner.',
          'If a parking owner cancels a confirmed booking, or fails to provide '
              'the space as described, the user is entitled to a full refund '
              'of the amount paid, and we may suspend the listing while we '
              'investigate.',
        ],
      ),
      LegalSection(
        number: '8',
        heading: 'Access Hours, Security and Vehicle Safety',
        paragraphs: [
          'Parking is available only during the access hours shown in the '
              'listing. Parking outside those hours, or blocking gates, ramps, '
              'driveways or other vehicles, is not permitted.',
          'Owners must hand over a space that is safe and reasonably fit for '
              'the purpose: no open manholes, no protruding metal, no oil '
              'spills, and no obstruction that prevents a vehicle from '
              'manoeuvring.',
          'Users must lock their vehicle, must not leave valuables visible, '
              'and must accept that parking is at their own risk to the extent '
              'permitted by law.',
          'CCTV, guards and other security measures are listed amenities. '
              'Their presence does not transfer responsibility for your '
              'vehicle to the owner or to ParkShare.',
        ],
      ),
      LegalSection(
        number: '9',
        heading: 'Prohibited Conduct and Acceptable Use',
        paragraphs: [
          'You must not use ParkShare to harass, threaten, defame or abuse '
              'any other user, and you must not post unlawful, infringing or '
              'offensive content, including in photographs and reviews.',
          'You must not attempt to gain unauthorised access to the platform or '
              'to any account, scrape or reverse-engineer the app, or '
              'interfere with its operation.',
          'You must not use a listing for commercial vehicle storage, '
              'warehousing, dismantling, repair work or any activity that is '
              'not ordinary vehicle parking, and you must not sublet a booked '
              'space to another person.',
          'Listing spaces with the deliberate intention of failing to provide '
              'them, and repeated no-shows by users, are considered abuse of '
              'the platform and may lead to suspension of the account.',
        ],
      ),
      LegalSection(
        number: '10',
        heading: 'Disputes, Liability and Indemnity',
        paragraphs: [
          'The in-app chat and our support channel are the first place to '
              'resolve any disagreement between an owner and a user. Please '
              'raise the issue promptly, and keep the booking reference and '
              'photographs to hand.',
          'To the fullest extent permitted by law, ParkShare is not liable for '
              'loss or damage arising from a listing that proves inaccurate, '
              'from the unavailability of a space at the time of arrival, or '
              'from the acts or omissions of an owner or a user.',
          'Each party is responsible for its own vehicle, its own property and '
              'its own compliance with these Terms, and each indemnifies the '
              'other against claims arising from that responsibility.',
          'Nothing in these Terms limits any liability that cannot lawfully be '
              'limited, including your statutory rights as a consumer.',
        ],
      ),
      LegalSection(
        number: '11',
        heading: 'Amendments to These Terms',
        paragraphs: [
          'We may revise these Terms to reflect changes in the platform, our '
              'operations or the law. The revised version takes effect as soon '
              'as it is published in the app.',
          'Where a change materially affects bookings that already exist, the '
              'terms agreed at the time of booking continue to apply to those '
              'bookings.',
          'Your continued use of the app after a revision is published means '
              'you accept the revised Terms.',
        ],
      ),
    ],
    contactHeading: 'Contact Us',
    contact: [
      'If you have any question about these Terms & Conditions, or need to '
          'raise a concern, please contact us:',
      'Email: $supportEmail',
      'Phone: $supportPhone',
      'Support hours: Monday to Saturday, 9:00 AM to 8:00 PM IST.',
      'Please include your booking or listing reference so we can help you '
          'quickly.',
    ],
  );

  // ------------------------------------------------------------------
  // Privacy Policy
  // ------------------------------------------------------------------
  static const LegalDocument privacy = LegalDocument(
    title: 'ParkShare Privacy Policy',
    lastUpdated: 'Last updated: 1 October 2026',
    intro:
        'This Privacy Policy explains what personal information ParkShare '
        'collects, why we collect it, who we share it with, how long we keep '
        'it and the choices you have. It applies to both parking owners and '
        'vehicle users of the ParkShare app.',
    sections: [
      LegalSection(
        number: '1',
        heading: 'Information We Collect',
        paragraphs: [
          'Account information: your full name, mobile number, email address, '
              'password (stored securely hashed, never in plain text) and, where '
              'provided, the UPI ID.',
          'Profile and listing information: the parking details you submit, '
              'including address, coordinates, plot and gate dimensions, space '
              'counts, amenities, access hours, rent and the photographs you '
              'upload.',
          'Booking and vehicle information: the space you book, the booking '
              'reference, the period of the booking, the vehicle registration '
              'number, make and model, and the payment method and transaction '
              'reference used.',
          'Technical information: your device model, operating system, app '
              'version, IP address, crash and diagnostic logs, and the pages '
              'or screens you use.',
          'Communications: messages you send to another user through the '
              'in-app chat, and any correspondence you have with our support '
              'team.',
        ],
      ),
      LegalSection(
        number: '2',
        heading: 'How We Use Your Information',
        paragraphs: [
          'To create and operate your account, to show you your bookings, '
              'listings, earnings, chat history and notifications.',
          'To match vehicle users with parking spaces: your approximate or '
              'exact location is used to search nearby listings and to show '
              'the parking spaces on the map.',
          'To process payments, issue receipts, record Cash on Delivery '
              'collections and calculate owner earnings.',
          'To prevent fraud and abuse, including duplicate accounts, fake '
              'listings, no-shows and attempts to circumvent slot limits.',
          'To communicate with you about a booking, a listing, a payment or '
              'a change to the platform.',
          'To understand how the app is used so we can fix errors and improve '
              'it. We rely on aggregated and de-identified usage data for this '
              'and do not use it to identify you individually.',
          'To meet legal, tax and regulatory obligations.',
        ],
      ),
      LegalSection(
        number: '3',
        heading: 'How We Share Your Information',
        paragraphs: [
          'With the other party to a booking: an owner sees the name, contact '
              'number, vehicle details and booking period of a user who books '
              'their space, and a user sees the owner\'s name and contact '
              'number for that booking. This information is shared only '
              'because the booking cannot be completed without it.',
          'With our payment partners, to the extent needed to process an '
              'online payment or to record a Cash on Delivery collection and '
              'issue a receipt.',
          'With service providers who host our servers, send messages, '
              'deliver push notifications or provide analytics, under contract '
              'and only for the purpose we specify.',
          'With authorities or litigants where disclosure is required by law, '
              'by a court order, or where necessary to protect the rights, '
              'property or safety of ParkShare, our users or the public.',
          'With a buyer or successor in the event of a merger, acquisition or '
              'sale of all or part of ParkShare, in which case your '
              'information will continue to be handled under this policy.',
          'We do not sell your personal information to third parties for '
              'their own marketing.',
        ],
      ),
      LegalSection(
        number: '4',
        heading: 'Payments and Financial Information',
        paragraphs: [
          'Payment processing is handled by third-party payment service '
              'providers. We never see or store your full card number, PIN, '
              'CVV or UPI PIN.',
          'We keep only what we need to administer a booking: the payment '
              'method, the amount, the transaction or receipt reference, the '
              'status and the timestamp of the payment or cash collection.',
          'Parking owners see the amount and the payment reference for their '
              'own earnings. Vehicle users see the amount they paid and the '
              'refund or receipt details for their own bookings.',
        ],
      ),
      LegalSection(
        number: '5',
        heading: 'Cookies and Local Storage',
        paragraphs: [
          'The app stores your session token on the device so you stay signed '
              'in, and small amounts of preference data such as your chosen '
              'role and map settings.',
          'We do not use advertising cookies or third-party advertising '
              'trackers.',
          'Signing out removes the session data from the device. If you '
              'uninstall the app, local data is deleted with it.',
        ],
      ),
      LegalSection(
        number: '6',
        heading: 'Location Data and Permissions',
        paragraphs: [
          'The app asks for location permission to show your position on the '
              'map, to search for parking near you, to drop a pin for a '
              'listing, and to record the location of a booking.',
          'If you decline the permission, you can still use the app by '
              'searching for an area or an address instead of using your '
              'current position.',
          'You can turn location access off at any time in your device '
              'settings. Without it, some map features will not work.',
          'Approximate location is used for the general map search; the '
              'precise coordinates you choose for a listing are stored with '
              'that listing and shown to users who book it.',
        ],
      ),
      LegalSection(
        number: '7',
        heading: 'Data Retention',
        paragraphs: [
          'We keep account and booking information for as long as your '
              'account is active, because it is needed to administer your '
              'bookings, listings and earnings.',
          'Financial and transaction records are retained for the period '
              'required by applicable law, including tax and accounting '
              'obligations.',
          'Messages you delete in the app may still be retained where we must '
              'keep them to resolve a dispute or comply with a legal '
              'obligation.',
          'When you close your account we delete or anonymise your personal '
              'information, except for the records we are legally required to '
              'retain.',
        ],
      ),
      LegalSection(
        number: '8',
        heading: 'Data Security',
        paragraphs: [
          'Your password is stored as a salted hash and is never stored or '
              'transmitted in plain text. All traffic between the app and our '
              'servers is encrypted in transit.',
          'Access to personal information is restricted to staff and service '
              'providers who need it to operate the platform, and is granted '
              'on a least-privilege basis.',
          'No system is completely secure. If we become aware of a breach that '
              'affects your information, we will notify you and the relevant '
              'authority as required by law.',
        ],
      ),
      LegalSection(
        number: '9',
        heading: 'Your Rights and Choices',
        paragraphs: [
          'You can view and edit your profile, listings, bookings and '
              'transactions from within the app.',
          'You can ask us for a copy of the personal information we hold '
              'about you, ask us to correct it, or ask us to delete your '
              'account. Write to us at the address in the contact section and '
              'we will respond within the period required by law.',
          'Where we rely on consent, you can withdraw it at any time. Consent '
              'to these Terms and to this Privacy Policy is collected on the '
              'Create Account screen and is required to use the app.',
          'You may choose not to grant location, camera or photo-library '
              'permission, and you may opt out of promotional messages by '
              'using the unsubscribe link in any message.',
          'We do not sell your personal information, so there is nothing to '
              'opt out of on that front.',
        ],
      ),
      LegalSection(
        number: '10',
        heading: "Children's Privacy",
        paragraphs: [
          'ParkShare is not intended for anyone under 18, and we do not '
              'knowingly collect information from children.',
          'If you believe a child has created an account or provided personal '
              'information to us, please contact us and we will delete it.',
        ],
      ),
      LegalSection(
        number: '11',
        heading: 'Changes to This Privacy Policy',
        paragraphs: [
          'We may update this Privacy Policy from time to time. The version '
              'in force is always the one published in the app, with its last '
              'updated date shown on t his screen.',
          'Where a change materially affects how we use information you have '
              'already given us, we will tell you before the change takes '
              'effect.',
          'Your continued use of the app after a change is published means you '
              'accept the updated Privacy Policy.',
        ],
      ),
    ],
    contactHeading: 'Contact Us',
    contact: [
      'For any privacy question, or to exercise a right described in section '
          '9, please contact us:',
      'Email: $supportEmail',
      'Phone: $supportPhone',
      'Support hours: Monday to Saturday, 9:00 AM to 8:00 PM IST.',
      'Please describe your concern clearly and, if it concerns a specific '
          'booking, include the booking reference.',
    ],
  );
}