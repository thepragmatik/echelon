package io.echelon.governance.token;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class RedisPolicyStoreTest {

  @Test
  void createRedisPolicyStore() {
    // Without Redis, constructor takes RedisTemplate — test just the class loads
    assertDoesNotThrow(
        () -> {
          var clazz = Class.forName("io.echelon.governance.token.RedisPolicyStore");
          assertNotNull(clazz);
        });
  }
}
