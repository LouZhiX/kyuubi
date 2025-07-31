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

package org.apache.kyuubi.server.http.authentication

import java.util.{Collections, Properties}
import javax.servlet.http.{HttpServletRequest, HttpServletResponse}

import org.apache.commons.lang3.StringUtils
import org.apache.hadoop.security.authentication.server.AuthenticationToken
import org.apache.hadoop.security.authentication.util.KerberosName

import org.apache.kyuubi.Logging
import org.apache.kyuubi.config.KyuubiConf
import org.apache.kyuubi.config.KyuubiConf._

/**
 * Knox authentication handler for Kyuubi.
 * This handler processes authentication information passed by Apache Knox gateway
 * through HTTP headers and creates appropriate authentication tokens.
 */
class KnoxAuthenticationHandler extends KyuubiHttpAuthenticationHandler with Logging {

  private var knoxEnabled: Boolean = _
  private var knoxAuthEnabled: Boolean = _
  private var knoxPrincipalHeader: String = _
  private var knoxGroupsHeader: String = _
  private var authType: String = _

  override def getType: String = KnoxAuthenticationHandler.TYPE

  override def init(config: Properties): Unit = {
    val conf = new KyuubiConf()
    
    knoxEnabled = conf.get(KNOX_PROXY_ENABLED)
    knoxAuthEnabled = conf.get(KNOX_AUTHENTICATION_ENABLED)
    knoxPrincipalHeader = conf.get(KNOX_PRINCIPAL_HEADER)
    knoxGroupsHeader = conf.get(KNOX_GROUPS_HEADER)
    authType = getType

    info(s"Knox authentication handler initialized: " +
      s"knoxEnabled=$knoxEnabled, knoxAuthEnabled=$knoxAuthEnabled, " +
      s"principalHeader=$knoxPrincipalHeader, groupsHeader=$knoxGroupsHeader")
  }

  override def destroy(): Unit = {
    // Nothing to clean up
  }

  override def managementOperation(
      token: AuthenticationToken,
      request: HttpServletRequest,
      response: HttpServletResponse): Boolean = {
    false // No management operations supported
  }

  override def authenticate(
      request: HttpServletRequest,
      response: HttpServletResponse): AuthenticationToken = {

    if (!knoxEnabled || !knoxAuthEnabled) {
      debug("Knox authentication is disabled, returning null token")
      return null
    }

    val principal = extractPrincipal(request)
    if (StringUtils.isEmpty(principal)) {
      debug("No Knox principal found in request headers")
      return null
    }

    val groups = extractGroups(request)
    val token = createAuthenticationToken(principal, groups)
    
    info(s"Knox authentication successful for user: $principal")
    debug(s"Knox authentication token created: $token")
    
    token
  }

  /**
   * Extract the principal (username) from Knox headers
   */
  private def extractPrincipal(request: HttpServletRequest): String = {
    val rawPrincipal = request.getHeader(knoxPrincipalHeader)
    if (StringUtils.isEmpty(rawPrincipal)) {
      // Try alternative headers
      val altHeaders = Seq("X-Forwarded-User", "Remote-User", "REMOTE_USER")
      altHeaders.map(request.getHeader).find(StringUtils.isNotEmpty).orNull
    } else {
      // Handle Kerberos principal format if needed
      try {
        val kerberosName = new KerberosName(rawPrincipal)
        kerberosName.getShortName
      } catch {
        case _: Exception =>
          // If not a Kerberos principal, use as-is
          rawPrincipal
      }
    }
  }

  /**
   * Extract user groups from Knox headers
   */
  private def extractGroups(request: HttpServletRequest): java.util.Set[String] = {
    val groupsHeader = request.getHeader(knoxGroupsHeader)
    if (StringUtils.isEmpty(groupsHeader)) {
      // Try alternative headers
      val altHeaders = Seq("X-Forwarded-Groups", "Remote-Groups")
      val groups = altHeaders.map(request.getHeader).find(StringUtils.isNotEmpty)
      parseGroups(groups.orNull)
    } else {
      parseGroups(groupsHeader)
    }
  }

  /**
   * Parse groups from comma-separated string
   */
  private def parseGroups(groupsStr: String): java.util.Set[String] = {
    if (StringUtils.isEmpty(groupsStr)) {
      Collections.emptySet()
    } else {
      val groups = groupsStr.split(",").map(_.trim).filter(_.nonEmpty).toSet
      scala.collection.JavaConverters.setAsJavaSet(groups)
    }
  }

  /**
   * Create authentication token with principal and groups
   */
  private def createAuthenticationToken(
      principal: String, 
      groups: java.util.Set[String]): AuthenticationToken = {
    new AuthenticationToken(principal, principal, authType) {
      override def getGroups: java.util.Set[String] = groups
      
      override def toString: String = {
        s"AuthenticationToken{user='$principal', type='$authType', groups=$groups}"
      }
    }
  }

  /**
   * Validate Knox headers and request
   */
  private def validateKnoxRequest(request: HttpServletRequest): Boolean = {
    // Check for required Knox headers
    val hasKnoxHeaders = Seq(
      "X-Knox-Gateway",
      "X-Knox-Service", 
      "X-Knox-Topology",
      "X-Forwarded-Context"
    ).exists(header => StringUtils.isNotEmpty(request.getHeader(header)))

    if (!hasKnoxHeaders) {
      debug("Request does not contain Knox headers, might not be from Knox gateway")
      return false
    }

    // Additional validation can be added here (e.g., IP validation, signature verification)
    true
  }
}

object KnoxAuthenticationHandler {
  val TYPE: String = "knox"
}