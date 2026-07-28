package io.echelon.governance.benchmark;

import io.echelon.governance.token.PolicyEngine;
import io.echelon.governance.token.YamlPolicyLoader;
import io.echelon.governance.token.TokenAction;
import io.echelon.governance.token.EvaluationResult;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.openjdk.jmh.annotations.*;
import java.util.concurrent.TimeUnit;

@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@Fork(0)
@State(Scope.Benchmark)
public class PolicyEngineBenchmark {
    private PolicyEngine engine;
    private TokenAction action;

    @Setup
    public void setup() {
        var loader = new YamlPolicyLoader("policies/agent-types.yaml");
        engine = new PolicyEngine(loader, new SimpleMeterRegistry());
        action = new TokenAction("write_source", "implementer", "build");
    }

    @Benchmark
    public EvaluationResult evaluate() {
        return engine.evaluate(action);
    }
}
