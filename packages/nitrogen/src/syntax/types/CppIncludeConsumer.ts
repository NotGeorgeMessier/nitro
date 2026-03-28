/**
 * Where the generated file that contains `#include` lives on disk under
 * `nitrogen/generated/`, so we can emit correct relative paths when CocoaPods
 * preserves directory layout (`header_mappings_dir`).
 */
export type CppIncludeConsumer =
  | 'shared-c++'
  /** `nitrogen/generated/shared/c++/views/` */
  | 'shared-c++-views'
  /** `nitrogen/generated/ios/` (autolinking: umbrella, bridge, Autolinking.mm) */
  | 'ios-generated-root'
  /** `nitrogen/generated/ios/c++/` */
  | 'ios-c++'
  /** `nitrogen/generated/ios/c++/views/` */
  | 'ios-c++-views'

/**
 * User include path for a header emitted under `nitrogen/generated/shared/c++/`
 * (basename only), from various consumer directories.
 */
export function sharedCppRelativeUserInclude(
  basename: string,
  consumer: CppIncludeConsumer | undefined
): string {
  if (consumer == null || consumer === 'shared-c++') {
    return basename
  }
  switch (consumer) {
    case 'shared-c++-views':
      return `../${basename}`
    case 'ios-generated-root':
      return `../shared/c++/${basename}`
    case 'ios-c++':
      return `../../shared/c++/${basename}`
    case 'ios-c++-views':
      return `../../../shared/c++/${basename}`
  }
}

/** From `nitrogen/generated/ios/` into a private header under `ios/c++/`. */
export function iosRootToIosCxxPrivateInclude(basename: string): string {
  return `c++/${basename}`
}

/** From `nitrogen/generated/ios/c++/` into a header at `nitrogen/generated/ios/`. */
export function iosCxxToIosRootInclude(basename: string): string {
  return `../${basename}`
}

/** From `nitrogen/generated/ios/c++/views/` into `nitrogen/generated/ios/c++/`. */
export function iosCxxViewsToIosCxxInclude(basename: string): string {
  return `../${basename}`
}

/** From `nitrogen/generated/ios/c++/views/` into `nitrogen/generated/ios/`. */
export function iosCxxViewsToIosRootInclude(basename: string): string {
  return `../../${basename}`
}

/** From `nitrogen/generated/ios/c++/views/` into `nitrogen/generated/shared/c++/views/`. */
export function iosCxxViewsToSharedViewsInclude(basename: string): string {
  return `../../../shared/c++/views/${basename}`
}
