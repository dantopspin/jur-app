export type Locale = 'kk' | 'ru' | 'en';
export type Gender = 'woman' | 'man';
export type InterestedIn = 'women' | 'men' | 'everyone';
export type Level = 'beginner' | 'casual' | 'regular' | 'competitive';
export type Season = 'summer' | 'winter' | 'all';
export type SwipeKind = 'pass' | 'like' | 'super';

export interface Sport {
  code: string;
  season: Season;
  emoji: string;
  name_kk: string;
  name_ru: string;
  name_en: string;
  sort: number;
}

export interface CardSport {
  code: string;
  level: Level;
}

export interface Achievement {
  id?: string;
  title: string;
  result: string | null;
  sport: string | null;
}

/** What the server returns for another person (profile_card in SQL). */
export interface ProfileCard {
  id: string;
  member_no: number;
  name: string;
  age: number;
  city: string;
  bio: string | null;
  next_challenge: string | null;
  photos: string[];
  verified: boolean;
  is_host: boolean;
  events_attended: number;
  sports: CardSport[];
  achievements: Achievement[];
  // only in discover:
  shared_sports?: number;
  super_liked_me?: boolean;
  boosted?: boolean;
  /** "2025-11" — the month they joined (card back) */
  member_since?: string;
  // only in likes_received (Pro): the note they sent with their like
  note?: string | null;
  // only in event_people:
  my_swipe?: SwipeKind | null;
  checked_in?: boolean;
  open_to_meet?: boolean;
  /** dating = shown for dating, buddy = shown as a training partner (discover, picks) */
  match_mode?: MatchMode;
  mode?: Mode;
  /** set while they're on a trip (travel mode) */
  travel_city?: string | null;
  prompts?: PromptAnswer[];
}

export type Mode = 'dating' | 'buddy' | 'both';
export type MatchMode = 'dating' | 'buddy';
export const PROMPT_KEYS = [
  'perfect_sunday', 'slow_down_for', 'after_finish', 'proudest_finish', 'teach_me',
  'green_flag', 'season_love', 'first_date_idea', 'training_secret',
] as const;
export type PromptKey = (typeof PROMPT_KEYS)[number];
export interface PromptAnswer { key: PromptKey; answer: string }

/** Your own row from the profiles table. */
export interface MyProfile {
  id: string;
  member_no: number;
  name: string;
  birthdate: string;
  gender: Gender;
  interested_in: InterestedIn;
  age_min: number;
  age_max: number;
  city: string;
  bio: string | null;
  next_challenge: string | null;
  photos: string[];
  locale: Locale;
  referral_code: string;
  verification_status: 'none' | 'pending' | 'approved' | 'rejected';
  is_host: boolean;
  hidden: boolean;
  banned: boolean;
  mode: Mode;
  buddy_with: InterestedIn;
  travel_city: string | null;
  travel_until: string | null;
}

export interface Limits {
  pro: boolean;
  pro_until: string | null;
  likes_left: number | null;
  supers_left: number;
  boost_credits: number;
  free_boost_available: boolean;
  boosted_until: string | null;
  streak_days: number;
  referral_code: string;
}

export interface SwipeResult {
  ok: boolean;
  error?: 'like_limit' | 'super_limit' | 'not_found' | 'note_too_long';
  match_id?: string | null;
  used_credit?: boolean;
}

export interface MatchRow {
  match_id: string;
  created_at: string;
  kind: MatchMode;
  other: ProfileCard;
  last_message: { body: string; sender_id: string; created_at: string; kind: MessageKind } | null;
  unread: number;
}

export type MessageKind = 'text' | 'photo' | 'voice' | 'date';
export type Reaction = 'heart' | 'fire' | 'clap' | 'laugh' | 'thumbsup';

export interface DatePayload {
  sport: string | null;
  when: string;
  place: string;
  event_id: string | null;
  status: 'pending' | 'accepted' | 'declined';
}

export interface Message {
  id: string;
  match_id: string;
  sender_id: string;
  body: string;
  created_at: string;
  read_at: string | null;
  kind: MessageKind;
  reply_to: string | null;
  media_path: string | null;
  media_ms: number | null;
  /** date card, or the prompt an opening note was about */
  payload: (Partial<DatePayload> & { prompt?: PromptAnswer }) | null;
  updated_at: string | null;
  reactions?: { profile_id: string; reaction: Reaction }[];
  reply?: { id: string; body: string; kind: MessageKind; sender_id: string } | null;
}

export interface GroupMessage {
  id: string;
  sender_id: string;
  body: string;
  created_at: string;
  sender: { name: string; photo: string | null; member_no: number };
}

export interface DuoState {
  duo: { id: string; status: 'pending' | 'active'; i_invited: boolean; partner: ProfileCard } | null;
  invites: { id: string; from: ProfileCard }[];
  matches: { id: string; created_at: string; other: ProfileCard[];
    last_message: { body: string; created_at: string; sender_id: string } | null }[];
}

export interface EventItem {
  id: string;
  host_id: string | null;
  city: string;
  sport_code: string;
  title: string;
  description: string | null;
  meeting_point: string;
  starts_at: string;
  duration_min: number;
  capacity: number;
  level: 'all' | Level;
  price_kzt: number;
  cover_url: string | null;
  /** dastarkhan: what happens after (tea, coffee, a long table) */
  after_text: string | null;
  cancelled: boolean;
  going_count: number;
  i_am_going: boolean;
  i_checked_in: boolean;
  host: { id: string; name: string; photo: string | null } | null;
  club_id: string | null;
  club: { id: string; name: string } | null;
  /** people going who wear the gold wristband (open to meeting someone) */
  open_count: number;
  /** my wristband: true = gold (open to meet), false = blue (here for the sport), null = not going */
  i_am_open: boolean | null;
}

export interface Club {
  id: string;
  city: string;
  sport_code: string;
  name: string;
  description: string | null;
  schedule: string | null;
  organizer_id: string | null;
  cover_url: string | null;
  member_count: number;
  i_am_member: boolean;
  i_am_organizer: boolean;
  organizer: { id: string; name: string; photo: string | null; member_no: number } | null;
  next_event: { id: string; title: string; starts_at: string } | null;
  faces: string[];
  /** only from get_club */
  events?: EventItem[];
}

export interface ClubMessage {
  id: string;
  club_id: string;
  sender_id: string;
  body: string;
  created_at: string;
  sender: { name: string; photo: string | null; member_no: number };
}

export interface CityStatus {
  city: string;
  open: boolean;
  members: number;
  needed: number;
  my_invites: number;
}

export interface OkResult {
  ok: boolean;
  error?: string;
}
