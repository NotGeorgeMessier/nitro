import type { HybridObject } from 'react-native-nitro-modules'

// This is a simple Recognizer
export interface Recognizer
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  start(): void
  stop(): void
  onResult?: (data: string) => void
}
