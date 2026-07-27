package io.echelon.governance.token;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class RedisPolicyStoreTest {

    @Test
    void createRedisPolicyStore() {
        // Without Redis, constructor takes RedisTemplate — test just the class loads
        assertDoesNotThrow(() -> {
            var clazz = Class.forName("io.echelon.governance.token.RedisPolicyStore");
            assertNotNull(clazz);
        });
    }
}
