// Thin typed wrappers over the SQL RPCs (see supabase/migrations).
import { supabase } from './supabase';
import type {
  CityStatus, Club, ClubMessage, DuoState, EventItem, GroupMessage, MatchMode, PromptAnswer, Reaction, Limits, MatchRow, Message, MyProfile, OkResult, ProfileCard, Sport,
  SwipeKind, SwipeResult,
} from './types';

async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args ?? {});
  if (error) throw new Error(error.message);
  return data as T;
}

export const api = {
  // ---- profile ----
  async myProfile(): Promise<MyProfile | null> {
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) return null;
    const { data, error } = await supabase.from('profiles').select('*').eq('id', auth.user.id).maybeSingle();
    if (error) throw new Error(error.message);
    return data as MyProfile | null;
  },
  async mySports(): Promise<{ sport_code: string; level: string }[]> {
    const { data, error } = await supabase.from('profile_sports').select('sport_code, level');
    if (error) throw new Error(error.message);
    return data ?? [];
  },
  async myAchievements(): Promise<{ id: string; sport_code: string | null; title: string; result: string | null }[]> {
    const { data, error } = await supabase
      .from('achievements').select('id, sport_code, title, result').order('created_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data ?? [];
  },
  async sports(): Promise<Sport[]> {
    const { data, error } = await supabase.from('sports').select('*').order('sort');
    if (error) throw new Error(error.message);
    return (data ?? []) as Sport[];
  },
  getProfile: (id: string) => rpc<ProfileCard | null>('get_profile', { p_id: id }),

  // ---- discover ----
  discover: (limit = 20, mode?: MatchMode) =>
    rpc<ProfileCard[]>('discover', mode ? { p_limit: limit, p_mode: mode } : { p_limit: limit }),
  /** prompt = the prompt key the note is about (Hinge-style "like this answer") */
  swipe: (target: string, kind: SwipeKind, note?: string, prompt?: string) =>
    rpc<SwipeResult>('swipe', { p_target: target, p_kind: kind, p_note: note?.trim() || null, p_prompt: prompt ?? null }),
  rewind: () => rpc<OkResult & { profile?: ProfileCard }>('rewind'),
  dailyPicks: () => rpc<ProfileCard[]>('daily_picks'),
  setTravel: (city: string, days: number) => rpc<OkResult & { until?: string }>('set_travel', { p_city: city, p_days: days }),
  clearTravel: () => rpc<void>('clear_travel'),

  // ---- prompts ----
  async savePrompts(userId: string, prompts: PromptAnswer[]) {
    const { error: e1 } = await supabase.from('profile_prompts').delete().eq('profile_id', userId);
    if (e1) throw new Error(e1.message);
    const rows = prompts.filter((p) => p.answer.trim().length >= 2).slice(0, 3)
      .map((p, i) => ({ profile_id: userId, position: i, prompt_key: p.key, answer: p.answer.trim() }));
    if (!rows.length) return;
    const { error } = await supabase.from('profile_prompts').insert(rows);
    if (error) throw new Error(error.message);
  },
  async myPrompts(): Promise<PromptAnswer[]> {
    const { data, error } = await supabase.from('profile_prompts').select('prompt_key, answer').order('position');
    if (error) throw new Error(error.message);
    return (data ?? []).map((r: { prompt_key: string; answer: string }) => ({ key: r.prompt_key as PromptAnswer['key'], answer: r.answer }));
  },

  // ---- hide from contacts ----
  setContactHides: (hashes: string[]) => rpc<number>('set_contact_hides', { p_hashes: hashes }),
  setPhoneHash: (hash: string | null) => rpc<void>('set_phone_hash', { p_hash: hash }),
  contactHidesCount: () => rpc<number>('contact_hides_count'),
  limits: () => rpc<Limits>('my_limits'),
  likesReceived: () => rpc<{ count: number; profiles: ProfileCard[] }>('likes_received'),
  activateBoost: () => rpc<OkResult & { boosted_until?: string }>('activate_boost'),
  recordActivity: () => rpc<{ streak_days: number; rewarded_boost: boolean } | null>('record_activity'),
  redeemReferral: (code: string) => rpc<OkResult>('redeem_referral', { p_code: code }),

  // ---- matches & chat ----
  matches: () => rpc<MatchRow[]>('my_matches'),
  markRead: (matchId: string) => rpc<void>('mark_read', { p_match: matchId }),
  unmatch: (matchId: string) => rpc<void>('unmatch', { p_match: matchId }),
  /** Upcoming events both people in this match have joined. */
  sharedEvents: (matchId: string) => rpc<EventItem[]>('shared_events', { p_match: matchId }),

  // ---- push ----
  registerPushToken: (token: string, platform: 'ios' | 'android') =>
    rpc<void>('register_push_token', { p_token: token, p_platform: platform }),
  unregisterPushToken: (token: string) => rpc<void>('unregister_push_token', { p_token: token }),
  /** Messages with reactions and reply previews, newest first. */
  chatMessages: (matchId: string, before?: string) =>
    rpc<Message[]>('chat_messages', before ? { p_match: matchId, p_before: before } : { p_match: matchId }),
  react: (messageId: string, reaction: Reaction) => rpc<void>('react', { p_message: messageId, p_reaction: reaction }),
  proposeDate: (matchId: string, d: { sport?: string | null; when?: string | null; place?: string | null; eventId?: string | null }) =>
    rpc<OkResult & { message_id?: string }>('propose_date', {
      p_match: matchId, p_sport: d.sport ?? null, p_when: d.when ?? null, p_place: d.place ?? null, p_event: d.eventId ?? null,
    }),
  respondDate: (messageId: string, answer: 'accepted' | 'declined') =>
    rpc<OkResult>('respond_date', { p_message: messageId, p_answer: answer }),
  async sendMedia(matchId: string, senderId: string, m: { kind: 'photo' | 'voice'; path: string; ms?: number; replyTo?: string | null }) {
    const { error } = await supabase.from('messages').insert({
      match_id: matchId, sender_id: senderId, body: '', kind: m.kind, media_path: m.path, media_ms: m.ms ?? null,
      reply_to: m.replyTo ?? null,
    });
    if (error) throw new Error(error.message);
  },

  // ---- double dates ----
  myDuo: () => rpc<DuoState>('my_duo'),
  duoInvite: (memberNo: number) => rpc<OkResult>('duo_invite', { p_member_no: memberNo }),
  duoRespond: (id: string, accept: boolean) => rpc<OkResult>('duo_respond', { p_duo: id, p_accept: accept }),
  duoLeave: () => rpc<void>('duo_leave'),
  duoDiscover: () => rpc<{ duo_id: string; members: ProfileCard[] }[]>('duo_discover'),
  duoSwipe: (duoId: string, kind: 'like' | 'pass') => rpc<OkResult & { match_id?: string | null }>('duo_swipe', { p_duo: duoId, p_kind: kind }),
  duoFeed: (matchId: string, before?: string) =>
    rpc<GroupMessage[]>('duo_feed', before ? { p_match: matchId, p_before: before } : { p_match: matchId }),
  async sendDuoMessage(matchId: string, senderId: string, body: string) {
    const { error } = await supabase.from('duo_messages').insert({ duo_match_id: matchId, sender_id: senderId, body: body.trim() });
    if (error) throw new Error(error.message);
  },

  async messages(matchId: string, before?: string): Promise<Message[]> {
    let q = supabase.from('messages').select('*').eq('match_id', matchId)
      .order('created_at', { ascending: false }).limit(50);
    if (before) q = q.lt('created_at', before);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    return (data ?? []) as Message[];
  },
  async send(matchId: string, senderId: string, body: string, replyTo?: string | null): Promise<Message> {
    const { data, error } = await supabase.from('messages')
      .insert({ match_id: matchId, sender_id: senderId, body: body.trim(), reply_to: replyTo ?? null })
      .select('*').single();
    if (error) throw new Error(error.message);
    return data as Message;
  },

  // ---- safety ----
  async block(me: string, other: string) {
    const { error } = await supabase.from('blocks').insert({ blocker_id: me, blocked_id: other });
    if (error && !error.message.includes('duplicate')) throw new Error(error.message);
  },
  async report(me: string, other: string, reason: string, details?: string) {
    const { error } = await supabase.from('reports')
      .insert({ reporter_id: me, reported_id: other, reason, details: details ?? null });
    if (error && !error.message.includes('duplicate')) throw new Error(error.message);
  },
  requestVerification: (path: string) => rpc<void>('request_verification', { p_selfie_path: path }),
  /** Deletes the account and its stored files (photos, selfies, chat media) via the delete-account function. */
  deleteAccount: async () => {
    const { error } = await supabase.functions.invoke('delete-account', { method: 'POST' });
    if (error) throw new Error(error.message);
  },

  // ---- events ----
  upcomingEvents: (city?: string) => rpc<EventItem[]>('upcoming_events', city ? { p_city: city } : {}),
  event: (id: string) => rpc<EventItem | null>('get_event', { p_id: id }),
  /** open = gold wristband (open to meeting someone), false = blue (here for the sport) */
  joinEvent: (id: string, open = true) => rpc<OkResult>('join_event', { p_event: id, p_open: open }),
  setOpenToMeet: (id: string, open: boolean) => rpc<void>('set_open_to_meet', { p_event: id, p_open: open }),

  // ---- clubs ----
  clubs: (city?: string) => rpc<Club[]>('clubs_near', city ? { p_city: city } : {}),
  club: (id: string) => rpc<Club | null>('get_club', { p_id: id }),
  joinClub: (id: string) => rpc<OkResult>('join_club', { p_id: id }),
  leaveClub: (id: string) => rpc<void>('leave_club', { p_id: id }),
  clubFeed: (id: string, before?: string) =>
    rpc<ClubMessage[]>('club_feed', before ? { p_club: id, p_before: before } : { p_club: id }),
  async sendClubMessage(clubId: string, senderId: string, body: string) {
    const { error } = await supabase.from('club_messages').insert({ club_id: clubId, sender_id: senderId, body: body.trim() });
    if (error) throw new Error(error.message);
  },
  applyClub: (city: string, sport: string, name: string, about: string) =>
    rpc<OkResult>('apply_club', { p_city: city, p_sport: sport, p_name: name, p_about: about }),

  // ---- city launch ----
  cityStatus: () => rpc<CityStatus>('city_status'),
  leaveEvent: (id: string) => rpc<void>('leave_event', { p_event: id }),
  checkIn: (id: string) => rpc<OkResult>('check_in', { p_event: id }),
  eventPeople: (id: string) => rpc<ProfileCard[]>('event_people', { p_event: id }),
  async createEvent(e: {
    host_id: string; city: string; sport_code: string; title: string; description: string | null;
    meeting_point: string; starts_at: string; duration_min: number; capacity: number; price_kzt: number;
    after_text: string | null; club_id?: string | null;
  }) {
    const { data, error } = await supabase.from('events').insert(e).select('id').single();
    if (error) throw new Error(error.message);
    return data as { id: string };
  },
};
