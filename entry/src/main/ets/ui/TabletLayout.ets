export function isTabletLandscape(area: Area): boolean {
  const width = Number(area.width);
  const height = Number(area.height);
  return height > 0 && width >= 720 && width > height;
}
