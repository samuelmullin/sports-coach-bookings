/**
 * Local shapes for the coach API responses.
 *
 * The OpenAPI spec types the roster/player `player` payload as
 * `{ [key: string]: unknown }` (it is `Players.summary_for_roster/1` server
 * side), so the fields the coach UI relies on are declared here explicitly.
 */

export type { CoachRosterEntry, CoachSessionEntry } from '../../api/endpoints';

export interface CoachEmergencyContact {
  name: string;
  relationship?: string | null;
  phone?: string | null;
}

export interface CoachPlayerSummary {
  id: string;
  name: string;
  full_name?: string;
  age?: number;
  preferred_positions?: string[];
  has_medical_info?: boolean;
  emergency_contact?: CoachEmergencyContact | null;
}

export interface CoachFeedbackVisibility {
  visibility: 'internal' | 'shared';
  shared_at?: string | null;
  edited_at?: string | null;
}

export interface CoachFeedbackSummary extends CoachFeedbackVisibility {
  id: string;
  session_id: string;
  player_id: string;
  coach_id: string;
}

export interface CoachFeedbackRecord extends CoachFeedbackVisibility {
  id: string;
  session_id: string;
  player_id: string;
  coach_id: string;
  body: string;
  skill_ratings?: Record<string, number>;
  focus_next?: string | null;
  inserted_at?: string | null;
  updated_at?: string | null;
}

export interface CoachPlayerProfile {
  home_club?: string | null;
  team?: string | null;
  preferred_positions?: string[];
  dominant_foot?: string | null;
  goals?: string | null;
  interests?: string | null;
  notes_from_family?: string | null;
}

export interface CoachPlayerContact {
  id: string;
  name: string;
  relationship?: string | null;
  phone?: string | null;
  alt_phone?: string | null;
  priority?: number;
}

export interface CoachPlayerPickup {
  id: string;
  name: string;
  relationship?: string | null;
  phone?: string | null;
  notes?: string | null;
}

export interface CoachPlayer {
  id: string;
  first_name?: string;
  last_name?: string;
  preferred_name?: string | null;
  date_of_birth?: string | null;
  age?: number;
  active?: boolean;
  has_medical_info?: boolean;
  profile?: CoachPlayerProfile | null;
  emergency_contacts?: CoachPlayerContact[];
  authorized_pickups?: CoachPlayerPickup[];
}

export interface CoachPlayerDetail {
  player: CoachPlayer;
  feedback: CoachFeedbackRecord[];
}

export interface RosterPlayerAggregate extends CoachPlayerSummary {
  has_feedback?: boolean;
}
