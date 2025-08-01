/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.kyuubi.server

import org.apache.kyuubi.KyuubiFunSuite
import org.apache.kyuubi.config.KyuubiConf

class KnoxIntegrationServiceSuite extends KyuubiFunSuite {

  test("KnoxIntegrationService should be disabled by default") {
    val conf = new KyuubiConf()
    val service = new KnoxIntegrationService()
    
    assert(!service.isKnoxIntegrationEnabled)
    assert(service.getKnoxGatewayUrl.isEmpty)
  }

  test("KnoxIntegrationService should be enabled when configured") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    conf.set(KyuubiConf.KNOX_GATEWAY_URL, "https://localhost:8443")
    conf.set(KyuubiConf.KNOX_TOPOLOGY_NAME, "kyuubi")
    conf.set(KyuubiConf.KNOX_SERVICE_PATH, "/kyuubi")
    
    val service = new KnoxIntegrationService()
    service.initialize(conf)
    
    assert(service.isKnoxIntegrationEnabled)
    assert(service.getKnoxGatewayUrl.contains("https://localhost:8443/gateway/kyuubi/kyuubi"))
  }

  test("KnoxIntegrationService should validate required configuration") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    // Missing required configuration
    
    val service = new KnoxIntegrationService()
    
    val exception = intercept[IllegalArgumentException] {
      service.initialize(conf)
    }
    
    assert(exception.getMessage.contains("Knox Gateway URL is required"))
  }

  test("KnoxIntegrationService should validate gateway URL format") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    conf.set(KyuubiConf.KNOX_GATEWAY_URL, "invalid-url")
    
    val service = new KnoxIntegrationService()
    
    val exception = intercept[IllegalArgumentException] {
      service.initialize(conf)
    }
    
    assert(exception.getMessage.contains("Invalid Knox Gateway URL"))
  }

  test("KnoxIntegrationService should handle default proxy users") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    conf.set(KyuubiConf.KNOX_GATEWAY_URL, "https://localhost:8443")
    conf.set(KyuubiConf.KNOX_TOPOLOGY_NAME, "kyuubi")
    
    val service = new KnoxIntegrationService()
    service.initialize(conf)
    
    assert(service.getKnoxProxyUsers.contains("knox"))
  }

  test("KnoxIntegrationService should handle custom proxy users") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    conf.set(KyuubiConf.KNOX_GATEWAY_URL, "https://localhost:8443")
    conf.set(KyuubiConf.KNOX_TOPOLOGY_NAME, "kyuubi")
    conf.set(KyuubiConf.KNOX_PROXY_USERS, Seq("user1", "user2"))
    
    val service = new KnoxIntegrationService()
    service.initialize(conf)
    
    assert(service.getKnoxProxyUsers.contains("user1"))
    assert(service.getKnoxProxyUsers.contains("user2"))
  }

  test("KnoxIntegrationService should handle SSL configuration") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    conf.set(KyuubiConf.KNOX_GATEWAY_URL, "https://localhost:8443")
    conf.set(KyuubiConf.KNOX_TOPOLOGY_NAME, "kyuubi")
    conf.set(KyuubiConf.KNOX_SSL_ENABLED, false)
    
    val service = new KnoxIntegrationService()
    service.initialize(conf)
    
    assert(!service.isKnoxSSLEnabled)
  }

  test("KnoxIntegrationService should handle authentication configuration") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    conf.set(KyuubiConf.KNOX_GATEWAY_URL, "https://localhost:8443")
    conf.set(KyuubiConf.KNOX_TOPOLOGY_NAME, "kyuubi")
    conf.set(KyuubiConf.KNOX_AUTHENTICATION_ENABLED, false)
    
    val service = new KnoxIntegrationService()
    service.initialize(conf)
    
    assert(!service.isKnoxAuthenticationEnabled)
  }

  test("KnoxIntegrationService should handle service lifecycle") {
    val conf = new KyuubiConf()
    conf.set(KyuubiConf.KNOX_INTEGRATION_ENABLED, true)
    conf.set(KyuubiConf.KNOX_GATEWAY_URL, "https://localhost:8443")
    conf.set(KyuubiConf.KNOX_TOPOLOGY_NAME, "kyuubi")
    
    val service = new KnoxIntegrationService()
    
    // Initialize
    service.initialize(conf)
    assert(service.getServiceState === org.apache.kyuubi.service.ServiceState.INITIALIZED)
    
    // Start
    service.start()
    assert(service.getServiceState === org.apache.kyuubi.service.ServiceState.STARTED)
    
    // Stop
    service.stop()
    assert(service.getServiceState === org.apache.kyuubi.service.ServiceState.STOPPED)
  }
}