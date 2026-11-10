"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, type ReactNode } from "react";
import { Menu, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { NAV_SECTIONS } from "./nav";

export function Sidebar({ companyName, footer }: { companyName: string; footer?: ReactNode }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <>
      <div className="flex items-center justify-between border-b bg-sidebar px-4 py-3 md:hidden print:hidden">
        <span className="font-semibold">{companyName}</span>
        <button type="button" aria-label="Open menu" onClick={() => setOpen((o) => !o)}>
          {open ? <X className="size-5" /> : <Menu className="size-5" />}
        </button>
      </div>
      <nav
        className={cn(
          "w-full shrink-0 border-r bg-sidebar text-sidebar-foreground md:block md:w-60 print:hidden",
          open ? "block" : "hidden",
        )}
      >
        <div className="hidden px-4 py-4 font-semibold md:block">{companyName}</div>
        {NAV_SECTIONS.map((section, i) => (
          <ul key={i} className="border-b px-2 py-2 last:border-b-0">
            {section.map((item) => {
              const active = pathname === item.href || pathname.startsWith(item.href + "/");
              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    onClick={() => setOpen(false)}
                    className={cn(
                      "block rounded-md px-3 py-1.5 text-sm hover:bg-sidebar-accent",
                      active && "bg-sidebar-accent font-medium text-sidebar-accent-foreground",
                    )}
                  >
                    {item.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        ))}
        {footer && <div className="border-t">{footer}</div>}
      </nav>
    </>
  );
}
