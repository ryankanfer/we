export const configuredSecretKeys = (
  namedKeysJSON: string | undefined,
): string[] => {
  const named: Record<string, unknown> = (() => {
    if (!namedKeysJSON) return {};
    try {
      const value = JSON.parse(namedKeysJSON);
      return value && typeof value === "object"
        ? value as Record<string, unknown>
        : {};
    } catch {
      return {};
    }
  })();

  const synthesisKey = named.synthesis;
  if (typeof synthesisKey === "string" && synthesisKey.length > 0) {
    return [synthesisKey];
  }

  return [];
};

export const authorizedSecretKey = (
  request: Request,
  configuredKeys: string[],
): string | null => {
  const supplied = request.headers.get("apikey");
  if (!supplied) return null;
  return configuredKeys.includes(supplied) ? supplied : null;
};
