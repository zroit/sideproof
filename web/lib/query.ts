import { useSyncExternalStore } from "react";

const still = () => () => {};

/** A query parameter of the page's URL: null while the static page is prerendered or hydrated,
 *  "" when the URL does not have it. */
export function useQuery(name: string): string | null {
  return useSyncExternalStore(still, () => new URLSearchParams(window.location.search).get(name) ?? "", () => null);
}
