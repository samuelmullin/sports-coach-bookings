import { Combobox } from '@scb/ui';
import type { PlayerResponse } from '../../api/endpoints';

export function PlayerSelect({
  players,
  value,
  onChange,
  placeholder = 'All players',
  id,
}: {
  players: PlayerResponse[];
  value?: string;
  onChange: (value: string | undefined) => void;
  placeholder?: string;
  id?: string;
}) {
  const options = [
    { value: '__all__', label: placeholder },
    ...players.map((player) => ({
      value: player.id,
      label: `${player.first_name} ${player.last_name}`,
    })),
  ];

  return (
    <Combobox
      id={id}
      aria-label="Player"
      options={options}
      value={value ?? '__all__'}
      onChange={(next) => onChange(next === '__all__' ? undefined : next)}
      placeholder={placeholder}
      searchPlaceholder="Find a player"
    />
  );
}
