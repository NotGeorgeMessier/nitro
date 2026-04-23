import * as React from 'react'

import {
  StyleSheet,
  View,
  Text,
  Button,
  Platform,
  Animated,
  useWindowDimensions,
} from 'react-native'
import { NitroModules } from 'react-native-nitro-modules'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { useColors } from '../useColors'
import {
  HybridRecognizer,
  HybridTestObjectSwiftKotlin,
} from 'react-native-nitro-test'
import { ExampleTurboModule } from '../turbo-module/ExampleTurboModule'

declare global {
  var gc: () => void
  var performance: {
    now: () => number
  }
}

interface BenchmarksResult {
  numberOfIterations: number
  nitroExecutionTimeMs: number
  turboExecutionTimeMs: number
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function waitForGc(): Promise<void> {
  gc()
  await delay(500)
}

interface BenchmarkableObject {
  addNumbers(a: number, b: number): number
}
function benchmark(obj: BenchmarkableObject): number {
  // warmup
  obj.addNumbers(0, 3)

  // run addNumbers(...) ITERATIONS amount of times
  const start = performance.now()
  let num = 0
  for (let i = 0; i < ITERATIONS; i++) {
    num = obj.addNumbers(num, 3)
  }
  const end = performance.now()
  return end - start
}

const ITERATIONS = 100_000
async function runBenchmarks(): Promise<BenchmarksResult> {
  console.log(`Running benchmarks ${ITERATIONS}x...`)
  await waitForGc()

  const turboTime = benchmark(ExampleTurboModule)
  const nitroTime = benchmark(HybridTestObjectSwiftKotlin)

  console.log(
    `Benchmarks finished! Nitro: ${nitroTime.toFixed(2)}ms | Turbo: ${turboTime.toFixed(2)}ms`
  )
  return {
    nitroExecutionTimeMs: nitroTime,
    turboExecutionTimeMs: turboTime,
    numberOfIterations: ITERATIONS,
  }
}

export function BenchmarksScreen() {
  const safeArea = useSafeAreaInsets()
  const colors = useColors()
  const [data, setData] = React.useState('')

  HybridRecognizer.onResult = (d) => setData(d)

  return (
    <View style={[styles.container, { paddingTop: safeArea.top }]}>
      <Text style={styles.header}>Benchmarks</Text>
      <View style={styles.topControls}>
        <View style={styles.flex} />
        <Text style={styles.buildTypeText}>{NitroModules.buildType}</Text>
      </View>

      <View style={styles.resultContainer}>
        <Text style={styles.text}>data: {data}</Text>
      </View>

      <View style={[styles.bottomView, { backgroundColor: colors.background }]}>
        <Button title="Start" onPress={() => HybridRecognizer.start()} />
      </View>
      <View style={[styles.bottomView, { backgroundColor: colors.background }]}>
        <Button title="Stop" onPress={() => HybridRecognizer.stop()} />
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  header: {
    fontSize: 26,
    fontWeight: 'bold',
    paddingBottom: 15,
    marginHorizontal: 15,
  },
  container: {
    flex: 1,
  },
  scrollContent: {},
  topControls: {
    marginHorizontal: 15,
    marginBottom: 10,
    flexDirection: 'row',
    alignItems: 'center',
  },
  buildTypeText: {
    fontFamily: Platform.select({
      ios: 'Menlo',
      macos: 'Menlo',
      android: 'monospace',
    }),
    fontWeight: 'bold',
  },
  segmentedControl: {
    minWidth: 180,
  },
  box: {
    width: 60,
    height: 60,
    marginVertical: 20,
  },
  testCase: {
    width: '100%',
    paddingHorizontal: 15,
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
  },
  testBox: {
    flexShrink: 1,
    flexDirection: 'column',
  },
  resultText: {
    flexShrink: 1,
  },
  testName: {
    fontSize: 16,
    fontWeight: 'bold',
  },
  testStatus: {
    fontSize: 14,
    flex: 1,
  },
  smallVSpacer: {
    height: 5,
  },
  largeVSpacer: {
    height: 25,
  },
  resultContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 45,
    marginHorizontal: 30,
  },
  chartsContainer: {
    alignItems: 'stretch',
  },
  nitroResults: {},
  turboResults: {},
  title: {
    fontWeight: 'bold',
    fontSize: 25,
  },
  chart: {
    height: 20,
    borderRadius: 5,
  },
  text: {
    fontSize: 16,
  },
  bold: {
    fontWeight: 'bold',
  },
  flex: { flex: 1 },
  bottomView: {
    borderTopRightRadius: 15,
    borderTopLeftRadius: 15,
    elevation: 15,
    shadowColor: 'black',
    shadowOffset: {
      width: 0,
      height: 5,
    },
    shadowRadius: 7,
    shadowOpacity: 0.4,

    paddingHorizontal: 15,
    paddingVertical: 9,
    alignItems: 'center',
    flexDirection: 'row',
  },
})
