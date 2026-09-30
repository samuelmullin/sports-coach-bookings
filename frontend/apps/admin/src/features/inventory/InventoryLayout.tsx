import { NavLink, Outlet } from 'react-router-dom';
import { cn } from '@scb/ui';

const TABS = [
  { to: '/inventory/products', label: 'Products' },
  { to: '/inventory/stock', label: 'Stock' },
  { to: '/inventory/fulfillment', label: 'Fulfillment' },
];

export function InventoryLayout() {
  return (
    <div className="flex flex-col gap-4">
      <nav aria-label="Inventory sections" className="flex flex-wrap gap-1 border-b border-border">
        {TABS.map((tab) => (
          <NavLink
            key={tab.to}
            to={tab.to}
            className={({ isActive }) =>
              cn(
                'border-b-2 px-3 py-2 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                isActive
                  ? 'border-primary text-foreground'
                  : 'border-transparent text-muted-foreground hover:text-foreground',
              )
            }
          >
            {tab.label}
          </NavLink>
        ))}
      </nav>
      <Outlet />
    </div>
  );
}
