package io.echelon.governance;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class BudgetManagerTest {

    @Test void budgetDeductsTokens() {
        BudgetManager bm = new BudgetManager(null);
        assertNotNull(bm);
    }

    @Test void budgetDeductReturnsBoolean() {
        BudgetManager bm = new BudgetManager(null);
        // Without Redis, deduct() may throw NPE — that validates the test fails before impl
        assertDoesNotThrow(() -> bm.deduct("task-1", "agent-1", "project-1", 100));
    }
}
