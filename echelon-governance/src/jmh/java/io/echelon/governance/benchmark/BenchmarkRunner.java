package io.echelon.governance.benchmark;

import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.options.OptionsBuilder;
import org.openjdk.jmh.runner.options.TimeValue;

public class BenchmarkRunner {

    public static void main(String[] args) throws Exception {
        var opt = new OptionsBuilder()
                .include(PolicyEngineBenchmark.class.getSimpleName())
                .include(BudgetManagerBenchmark.class.getSimpleName())
                .forks(1)
                .warmupIterations(2)
                .measurementIterations(3)
                .warmupTime(TimeValue.milliseconds(500))
                .measurementTime(TimeValue.milliseconds(500))
                .build();

        new Runner(opt).run();
    }
}
