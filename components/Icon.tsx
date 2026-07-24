"use client";

type Name =
  | "today" | "plan" | "home" | "profile" | "plus" | "people" | "heart"
  | "check" | "utensils" | "basket" | "receipt" | "plant" | "bell"
  | "chevron" | "spark" | "lock" | "calendar";

const P: Record<Name, React.ReactNode> = {
  today: <><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19" /></>,
  plan: <><rect x="3" y="4" width="18" height="17" rx="2" /><path d="M3 9h18M8 2v4M16 2v4" /></>,
  home: <path d="M3 11l9-7 9 7M5 10v10h14V10" />,
  profile: <><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4 4-6 8-6s8 2 8 6" /></>,
  plus: <path d="M12 5v14M5 12h14" />,
  people: <><circle cx="9" cy="8" r="3.2" /><circle cx="16" cy="9" r="2.6" /><path d="M3.5 20c0-3 2.5-4.5 5.5-4.5S14.5 17 14.5 20M15 15.5c2.5 0 5 1.4 5 4.5" /></>,
  heart: <path d="M12 20s-7-4.6-9.2-9C1.3 8 3 4.5 6.3 4.5c2 0 3.2 1.2 3.7 2 .5-.8 1.7-2 3.7-2C17 4.5 18.7 8 21.2 11 19 15.4 12 20 12 20z" />,
  check: <path d="M20 6L9 17l-5-5" />,
  utensils: <path d="M6 2v8a2 2 0 004 0V2M8 10v12M17 2c-1.5 0-2.5 2-2.5 5s1 4 2.5 4v11" />,
  basket: <><path d="M5 9h14l-1.4 10.2a2 2 0 01-2 1.8H8.4a2 2 0 01-2-1.8L5 9z" /><path d="M9 9l3-6 3 6" /></>,
  receipt: <><path d="M6 2h12v20l-3-2-3 2-3-2-3 2V2z" /><path d="M9 8h6M9 12h6" /></>,
  plant: <path d="M12 22v-8M12 14c0-3-2-6-6-6 0 3 2 6 6 6zM12 12c0-3 2-5 5-5 0 3-2 5-5 5z" />,
  bell: <path d="M18 8a6 6 0 10-12 0c0 7-3 8-3 8h18s-3-1-3-8M10 20a2 2 0 004 0" />,
  chevron: <path d="M9 6l6 6-6 6" />,
  spark: <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z" />,
  lock: <><rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 018 0v3" /></>,
  calendar: <><rect x="3" y="4" width="18" height="17" rx="2" /><path d="M3 9h18M8 2v4M16 2v4" /></>,
};

export default function Icon({
  name,
  size = 20,
  className = "",
  strokeWidth = 1.6,
}: {
  name: Name;
  size?: number;
  className?: string;
  strokeWidth?: number;
}) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      {P[name]}
    </svg>
  );
}
