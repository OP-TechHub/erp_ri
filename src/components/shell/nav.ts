/** Left menu – same labels and order as the reference app (ERP_Accounts_Module_v5.html). */
export type NavItem = { href: string; label: string };

export const NAV_SECTIONS: NavItem[][] = [
  [
    { href: "/dashboard", label: "Dashboard" },
    { href: "/sales", label: "Sales Entry" },
    { href: "/receipts", label: "Customer Receipts" },
    { href: "/purchases", label: "Purchase Entry" },
    { href: "/supplier-payments", label: "Supplier Payments" },
    { href: "/payments", label: "Payments Entry" },
  ],
  [
    { href: "/customers", label: "Customers" },
    { href: "/suppliers", label: "Suppliers" },
    { href: "/statement", label: "Outstanding Statement" },
    { href: "/outstanding", label: "Outstanding Report" },
    { href: "/sales-reports", label: "🧾 Sales Reports" },
  ],
  [
    { href: "/pl", label: "Profit & Loss" },
    { href: "/notes", label: "Notes to Accounts" },
  ],
  [
    { href: "/settings", label: "Settings" },
    { href: "/data", label: "Backup & Export" },
  ],
];

export const NAV_ITEMS: NavItem[] = NAV_SECTIONS.flat();
