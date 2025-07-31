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

package org.apache.kyuubi.server.ui

import java.net.{URI, URL}
import javax.servlet.http.{HttpServlet, HttpServletRequest, HttpServletResponse}

import org.apache.commons.lang3.StringUtils
import org.eclipse.jetty.client.HttpClient
import org.eclipse.jetty.client.api.Request
import org.eclipse.jetty.proxy.ProxyServlet
import org.eclipse.jetty.util.ssl.SslContextFactory

import org.apache.kyuubi.Logging
import org.apache.kyuubi.config.KyuubiConf
import org.apache.kyuubi.config.KyuubiConf._

/**
 * Knox proxy servlet for Kyuubi WebUI.
 * This servlet handles requests coming through Apache Knox gateway and forwards them
 * to the actual Kyuubi WebUI, handling path rewriting and header forwarding appropriately.
 */
private[kyuubi] class KnoxProxyServlet(conf: KyuubiConf) extends ProxyServlet with Logging {

  private val knoxEnabled = conf.get(KNOX_PROXY_ENABLED)
  private val knoxGatewayUrl = conf.get(KNOX_GATEWAY_URL)
  private val knoxServiceName = conf.get(KNOX_SERVICE_NAME)
  private val knoxTopologyName = conf.get(KNOX_TOPOLOGY_NAME)
  private val knoxContextPath = conf.get(KNOX_CONTEXT_PATH)
  private val knoxAuthEnabled = conf.get(KNOX_AUTHENTICATION_ENABLED)
  private val knoxPrincipalHeader = conf.get(KNOX_PRINCIPAL_HEADER)
  private val knoxGroupsHeader = conf.get(KNOX_GROUPS_HEADER)

  private val restBindHost = conf.get(FRONTEND_REST_BIND_HOST).getOrElse("localhost")
  private val restBindPort = conf.get(FRONTEND_REST_BIND_PORT)

  override def createHttpClient(): HttpClient = {
    val sslContextFactory = new SslContextFactory.Client()
    sslContextFactory.setTrustAll(true) // For development, in production use proper SSL configuration
    val httpClient = new HttpClient(sslContextFactory)
    httpClient.setFollowRedirects(false)
    httpClient
  }

  override def rewriteTarget(request: HttpServletRequest): String = {
    val requestURI = request.getRequestURI
    val queryString = request.getQueryString

    // Remove Knox context path prefix if present
    val cleanURI = if (requestURI.startsWith(knoxContextPath)) {
      requestURI.substring(knoxContextPath.length)
    } else {
      requestURI
    }

    // Build target URL pointing to local Kyuubi REST service
    val targetPath = if (cleanURI.isEmpty || cleanURI == "/") "/ui/" else cleanURI
    val targetURL = s"http://$restBindHost:$restBindPort$targetPath"
    
    val finalURL = if (StringUtils.isNotEmpty(queryString)) {
      s"$targetURL?$queryString"
    } else {
      targetURL
    }

    debug(s"Knox proxy rewrite: ${request.getRequestURL} => $finalURL")
    finalURL
  }

  override def addXForwardedHeaders(
      clientRequest: HttpServletRequest,
      proxyRequest: Request): Unit = {
    super.addXForwardedHeaders(clientRequest, proxyRequest)

    // Add Knox-specific headers
    if (knoxEnabled && knoxGatewayUrl.isDefined) {
      // Set X-Forwarded-Context for proper base path handling
      proxyRequest.header("X-Forwarded-Context", knoxContextPath)
      
      // Set Knox gateway information
      proxyRequest.header("X-Knox-Gateway", knoxGatewayUrl.get)
      proxyRequest.header("X-Knox-Service", knoxServiceName)
      proxyRequest.header("X-Knox-Topology", knoxTopologyName)
    }

    // Forward Knox authentication headers if enabled
    if (knoxAuthEnabled) {
      Option(clientRequest.getHeader(knoxPrincipalHeader)).foreach { principal =>
        proxyRequest.header("X-Forwarded-User", principal)
        proxyRequest.header("Remote-User", principal)
        debug(s"Forwarding Knox principal: $principal")
      }

      Option(clientRequest.getHeader(knoxGroupsHeader)).foreach { groups =>
        proxyRequest.header("X-Forwarded-Groups", groups)
        debug(s"Forwarding Knox groups: $groups")
      }
    }

    // Forward other Knox standard headers
    Seq("X-Forwarded-Proto", "X-Forwarded-Host", "X-Forwarded-Port", "X-Forwarded-Server")
      .foreach { headerName =>
        Option(clientRequest.getHeader(headerName)).foreach { headerValue =>
          proxyRequest.header(headerName, headerValue)
        }
      }
  }

  override def filterServerResponseHeader(
      clientRequest: HttpServletRequest,
      serverResponse: org.eclipse.jetty.client.api.Response,
      headerName: String,
      headerValue: String): String = {
    
    // Rewrite Location headers to use Knox gateway URL
    if ("Location".equalsIgnoreCase(headerName) && knoxGatewayUrl.isDefined) {
      try {
        val location = new URI(headerValue)
        if (location.getHost != null && location.getHost.equals(restBindHost) && 
            location.getPort == restBindPort) {
          // Rewrite internal URLs to use Knox gateway
          val knoxUrl = new URI(knoxGatewayUrl.get)
          val rewrittenPath = knoxContextPath + location.getPath
          val rewrittenLocation = new URI(
            knoxUrl.getScheme,
            knoxUrl.getUserInfo,
            knoxUrl.getHost,
            knoxUrl.getPort,
            s"/gateway/$knoxTopologyName$rewrittenPath",
            location.getQuery,
            location.getFragment
          ).toString
          debug(s"Rewriting Location header: $headerValue => $rewrittenLocation")
          return rewrittenLocation
        }
      } catch {
        case e: Exception =>
          warn(s"Failed to rewrite Location header: $headerValue", e)
      }
    }

    super.filterServerResponseHeader(clientRequest, serverResponse, headerName, headerValue)
  }

  /**
   * Handle requests that don't need proxying (e.g., health checks)
   */
  override def service(request: HttpServletRequest, response: HttpServletResponse): Unit = {
    val requestURI = request.getRequestURI
    
    // Handle Knox health check requests
    if (requestURI.endsWith("/health") || requestURI.endsWith("/ping")) {
      response.setStatus(HttpServletResponse.SC_OK)
      response.setContentType("application/json")
      response.getWriter.write("""{"status":"ok","service":"kyuubi-webui"}""")
      return
    }

    // Handle Knox service discovery requests
    if (requestURI.endsWith("/service-info")) {
      response.setStatus(HttpServletResponse.SC_OK)
      response.setContentType("application/json")
      val serviceInfo = s"""
        |{
        |  "service": "$knoxServiceName",
        |  "topology": "$knoxTopologyName",
        |  "contextPath": "$knoxContextPath",
        |  "version": "1.9.0",
        |  "authentication": $knoxAuthEnabled
        |}
      """.stripMargin
      response.getWriter.write(serviceInfo)
      return
    }

    // For all other requests, use the proxy functionality
    super.service(request, response)
  }
}