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

import java.net.URL
import java.util.concurrent.{Executors, ScheduledExecutorService, TimeUnit}

import org.apache.kyuubi.config.KyuubiConf
import org.apache.kyuubi.service.{AbstractService, ServiceState}
import org.apache.kyuubi.util.{Logging, ThreadUtils}

/**
 * Service for integrating Kyuubi WebUI with Apache Knox Gateway
 */
class KnoxIntegrationService extends AbstractService("KnoxIntegrationService") with Logging {

  private var executor: ScheduledExecutorService = _
  private var knoxHealthChecker: Runnable = _

  override def initialize(conf: KyuubiConf): Unit = {
    if (conf.get(KyuubiConf.KNOX_INTEGRATION_ENABLED)) {
      info("Initializing Knox Integration Service")
      
      // Validate Knox configuration
      validateKnoxConfig(conf)
      
      // Initialize health checker
      initHealthChecker(conf)
      
      super.initialize(conf)
    } else {
      info("Knox integration is disabled, skipping initialization")
    }
  }

  override def start(): Unit = {
    if (conf.get(KyuubiConf.KNOX_INTEGRATION_ENABLED)) {
      info("Starting Knox Integration Service")
      
      // Start health checker
      if (knoxHealthChecker != null) {
        executor = Executors.newSingleThreadScheduledExecutor()
        executor.scheduleWithFixedDelay(knoxHealthChecker, 0, 30, TimeUnit.SECONDS)
      }
      
      super.start()
    }
  }

  override def stop(): Unit = {
    if (conf.get(KyuubiConf.KNOX_INTEGRATION_ENABLED)) {
      info("Stopping Knox Integration Service")
      
      // Stop health checker
      if (executor != null) {
        ThreadUtils.shutdown(executor)
        executor = null
      }
      
      super.stop()
    }
  }

  private def validateKnoxConfig(conf: KyuubiConf): Unit = {
    val gatewayUrl = conf.get(KyuubiConf.KNOX_GATEWAY_URL)
    if (gatewayUrl.isEmpty) {
      throw new IllegalArgumentException(
        s"Knox Gateway URL is required when Knox integration is enabled. " +
        s"Please set ${KyuubiConf.KNOX_GATEWAY_URL.key}")
    }
    
    try {
      new URL(gatewayUrl.get)
    } catch {
      case e: Exception =>
        throw new IllegalArgumentException(
          s"Invalid Knox Gateway URL: ${gatewayUrl.get}", e)
    }
    
    val topologyName = conf.get(KyuubiConf.KNOX_TOPOLOGY_NAME)
    if (topologyName.isEmpty) {
      throw new IllegalArgumentException(
        s"Knox topology name is required. " +
        s"Please set ${KyuubiConf.KNOX_TOPOLOGY_NAME.key}")
    }
  }

  private def initHealthChecker(conf: KyuubiConf): Unit = {
    knoxHealthChecker = new Runnable {
      override def run(): Unit = {
        try {
          checkKnoxHealth(conf)
        } catch {
          case e: Exception =>
            warn("Failed to check Knox health", e)
        }
      }
    }
  }

  private def checkKnoxHealth(conf: KyuubiConf): Unit = {
    val gatewayUrl = conf.get(KyuubiConf.KNOX_GATEWAY_URL).get
    val topologyName = conf.get(KyuubiConf.KNOX_TOPOLOGY_NAME)
    val servicePath = conf.get(KyuubiConf.KNOX_SERVICE_PATH)
    
    val healthUrl = s"$gatewayUrl/gateway/$topologyName$servicePath/api/v1/info"
    
    try {
      val connection = new URL(healthUrl).openConnection()
      connection.setConnectTimeout(5000)
      connection.setReadTimeout(5000)
      
      val responseCode = connection.asInstanceOf[java.net.HttpURLConnection].getResponseCode
      if (responseCode == 200) {
        debug("Knox Gateway health check passed")
      } else {
        warn(s"Knox Gateway health check failed with response code: $responseCode")
      }
    } catch {
      case e: Exception =>
        warn(s"Knox Gateway health check failed: ${e.getMessage}")
    }
  }

  /**
   * Get the Knox Gateway URL for Kyuubi WebUI
   */
  def getKnoxGatewayUrl: Option[String] = {
    if (conf.get(KyuubiConf.KNOX_INTEGRATION_ENABLED)) {
      val gatewayUrl = conf.get(KyuubiConf.KNOX_GATEWAY_URL)
      val topologyName = conf.get(KyuubiConf.KNOX_TOPOLOGY_NAME)
      val servicePath = conf.get(KyuubiConf.KNOX_SERVICE_PATH)
      
      gatewayUrl.map(url => s"$url/gateway/$topologyName$servicePath")
    } else {
      None
    }
  }

  /**
   * Check if Knox integration is enabled
   */
  def isKnoxIntegrationEnabled: Boolean = {
    conf.get(KyuubiConf.KNOX_INTEGRATION_ENABLED)
  }

  /**
   * Get Knox proxy users
   */
  def getKnoxProxyUsers: Seq[String] = {
    conf.get(KyuubiConf.KNOX_PROXY_USERS)
  }

  /**
   * Check if SSL is enabled for Knox
   */
  def isKnoxSSLEnabled: Boolean = {
    conf.get(KyuubiConf.KNOX_SSL_ENABLED)
  }

  /**
   * Check if authentication is enabled for Knox
   */
  def isKnoxAuthenticationEnabled: Boolean = {
    conf.get(KyuubiConf.KNOX_AUTHENTICATION_ENABLED)
  }
}