// RevenueCat wrapper. Pro status shown in the app always comes from the
// server (my_limits), which RevenueCat updates through the webhook; the SDK
// is only used to sell and restore.
import Constants, { ExecutionEnvironment } from 'expo-constants';
import { Platform } from 'react-native';
import Purchases, {
  LOG_LEVEL, PACKAGE_TYPE, type PurchasesOffering, type PurchasesPackage,
} from 'react-native-purchases';
import { env } from './env';

export const OFFERING_PRO = 'default';
export const OFFERING_BOOSTS = 'boosts';
export const OFFERING_SUPERS = 'super_likes';
/** One-time 50% off first month (qadam_pro_monthly_intro), shown once when someone closes the paywall. */
export const OFFERING_INTRO = 'intro';
export const ENTITLEMENT_PRO = 'pro';

let configuredFor: string | null = null;

function apiKey(): string {
  return Platform.OS === 'ios' ? env.revenueCatIos : env.revenueCatAndroid;
}

/** False in Expo Go and when keys are missing: the UI then explains instead of crashing. */
export function purchasesAvailable(): boolean {
  return Constants.executionEnvironment !== ExecutionEnvironment.StoreClient && apiKey().length > 0;
}

export async function initPurchases(userId: string): Promise<void> {
  if (!purchasesAvailable() || configuredFor === userId) return;
  try {
    if (configuredFor === null) {
      if (__DEV__) Purchases.setLogLevel(LOG_LEVEL.WARN);
      Purchases.configure({ apiKey: apiKey(), appUserID: userId });
    } else {
      await Purchases.logIn(userId);
    }
    configuredFor = userId;
  } catch (e) {
    console.warn('RevenueCat init failed', e);
  }
}

export async function resetPurchases(): Promise<void> {
  if (configuredFor === null) return;
  try {
    await Purchases.logOut();
  } catch {
    // already anonymous
  }
  configuredFor = null;
}

export interface Offerings {
  pro: PurchasesOffering | null;
  boosts: PurchasesOffering | null;
  supers: PurchasesOffering | null;
  intro: PurchasesOffering | null;
}

export async function loadOfferings(): Promise<Offerings> {
  const all = await Purchases.getOfferings();
  return {
    pro: all.all[OFFERING_PRO] ?? all.current ?? null,
    boosts: all.all[OFFERING_BOOSTS] ?? null,
    supers: all.all[OFFERING_SUPERS] ?? null,
    intro: all.all[OFFERING_INTRO] ?? null,
  };
}

/** Returns true when the purchase went through, false when the user cancelled. */
export async function buy(pkg: PurchasesPackage): Promise<boolean> {
  try {
    await Purchases.purchasePackage(pkg);
    return true;
  } catch (e: unknown) {
    if (e && typeof e === 'object' && 'userCancelled' in e && (e as { userCancelled?: boolean }).userCancelled) {
      return false;
    }
    throw e;
  }
}

export async function restore(): Promise<boolean> {
  const info = await Purchases.restorePurchases();
  return Boolean(info.entitlements.active[ENTITLEMENT_PRO]);
}

export async function manageSubscriptionsUrl(): Promise<string | null> {
  try {
    const info = await Purchases.getCustomerInfo();
    return info.managementURL;
  } catch {
    return null;
  }
}

export function sortProPackages(pkgs: PurchasesPackage[]): PurchasesPackage[] {
  const order = [PACKAGE_TYPE.WEEKLY, PACKAGE_TYPE.MONTHLY, PACKAGE_TYPE.SIX_MONTH, PACKAGE_TYPE.ANNUAL];
  return [...pkgs].sort((a, b) => order.indexOf(a.packageType) - order.indexOf(b.packageType));
}

/** "5 boosts" style count from the product id (qadam_boost_5 → 5). */
export function packCount(pkg: PurchasesPackage): number {
  const m = pkg.product.identifier.match(/_(\d+)$/);
  return m ? Number(m[1]) : 1;
}
