// Photos stay in this browser (IndexedDB), never on the server: the first baseline, the latest
// scan with YouCam's overlays, and the simulated promise, per trial.

export type Saved = {
  baseline?: string; // data URLs
  latest?: string;
  overlays?: Record<string, string>;
  baselineOverlays?: Record<string, string>;
  midline?: [[number, number], [number, number]];
  promise?: string;
};

const DB = "sideproof", STORE = "photos";

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export async function load(trial: string): Promise<Saved> {
  try {
    const db = await open();
    return await new Promise((resolve) => {
      const req = db.transaction(STORE).objectStore(STORE).get(trial);
      req.onsuccess = () => resolve((req.result as Saved) ?? {});
      req.onerror = () => resolve({});
    });
  } catch {
    return {};
  }
}

export async function save(trial: string, patch: Saved): Promise<Saved> {
  const next = { ...(await load(trial)), ...patch };
  try {
    const db = await open();
    await new Promise<void>((resolve) => {
      const tx = db.transaction(STORE, "readwrite");
      tx.objectStore(STORE).put(next, trial);
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    });
  } catch {
    /* private mode: the pictures last for this visit only */
  }
  return next;
}

/** A camera or gallery file as a JPEG no larger than `longest` px, plus a data URL of it. */
export async function shrink(file: Blob, longest = 2048, quality = 0.92): Promise<{ blob: Blob; url: string }> {
  const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  const scale = Math.min(1, longest / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise<Blob>((resolve) => canvas.toBlob((b) => resolve(b!), "image/jpeg", quality));
  const small = document.createElement("canvas");
  const s2 = Math.min(1, 1080 / Math.max(canvas.width, canvas.height));
  small.width = Math.round(canvas.width * s2);
  small.height = Math.round(canvas.height * s2);
  small.getContext("2d")!.drawImage(canvas, 0, 0, small.width, small.height);
  return { blob, url: small.toDataURL("image/jpeg", 0.85) };
}

export async function blobOf(dataUrl: string): Promise<Blob> {
  return (await fetch(dataUrl)).blob();
}
