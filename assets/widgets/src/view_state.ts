const prefix = "basa:view:";

export function loadView<T>(key: string): T | null {
  try {
    const raw = sessionStorage.getItem(prefix + key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

export function saveView<T>(key: string, value: T) {
  try {
    sessionStorage.setItem(prefix + key, JSON.stringify(value));
  } catch {
  }
}
