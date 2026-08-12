/// Programmes offered at CSJM University, Kanpur (UIET & affiliated
/// institutes) — used for the registration dropdowns.
class Branch {
  final String key; // stable id stored in the database
  final String name; // full display name
  final String short; // abbreviation used in classroom codes
  final int years; // programme duration

  const Branch(this.key, this.name, this.short, this.years);
}

const List<Branch> kBranches = [
  // UIET — B.Tech
  Branch('btech_cse', 'B.Tech — Computer Science & Engineering', 'CSE', 4),
  Branch('btech_it', 'B.Tech — Information Technology', 'IT', 4),
  Branch('btech_ece', 'B.Tech — Electronics & Communication', 'ECE', 4),
  Branch('btech_ee', 'B.Tech — Electrical Engineering', 'EE', 4),
  Branch('btech_me', 'B.Tech — Mechanical Engineering', 'ME', 4),
  Branch('btech_ce', 'B.Tech — Civil Engineering', 'CE', 4),
  Branch('btech_che', 'B.Tech — Chemical Engineering', 'CHE', 4),
  Branch('btech_ft', 'B.Tech — Food Technology', 'FT', 4),
  Branch('btech_bt', 'B.Tech — Biotechnology', 'BT', 4),
  // Other undergraduate programmes
  Branch('bca', 'BCA — Computer Applications', 'BCA', 3),
  Branch('bba', 'BBA — Business Administration', 'BBA', 3),
  Branch('bcom', 'B.Com', 'BCOM', 3),
  Branch('bsc_math', 'B.Sc — Mathematics', 'BSM', 3),
  Branch('bsc_bio', 'B.Sc — Biology', 'BSB', 3),
  Branch('bsc_cs', 'B.Sc — Computer Science', 'BSC', 3),
  Branch('bpharm', 'B.Pharm — Pharmacy', 'BPH', 4),
  Branch('ballb', 'BA LLB (Hons.)', 'LAW', 5),
  Branch('bhmct', 'BHMCT — Hotel Management', 'HM', 4),
  // Postgraduate
  Branch('mba', 'MBA — Management', 'MBA', 2),
  Branch('mca', 'MCA — Computer Applications', 'MCA', 2),
];

Branch branchByKey(String key) =>
    kBranches.firstWhere((b) => b.key == key, orElse: () => kBranches.first);

const List<String> kYearNames = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
  '5th Year',
  '6th Year',
];

String yearName(int year) =>
    (year >= 1 && year <= kYearNames.length) ? kYearNames[year - 1] : 'Year $year';
