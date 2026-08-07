package com.kkape.demo.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Protects every demo API endpoint with a high-entropy bearer token. */
@Component
public class ApiAuthenticationFilter extends OncePerRequestFilter implements InitializingBean {

    @Value("${nanolink.api.token}")
    private String apiToken;

    @Override
    public void afterPropertiesSet() throws ServletException {
        super.afterPropertiesSet();
        if (apiToken == null || apiToken.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new ServletException("nanolink.api.token must be configured with at least 32 bytes");
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/");
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        String authorization = request.getHeader("Authorization");
        String token = "";
        if (authorization != null) {
            String[] parts = authorization.trim().split("\\s+", 2);
            if (parts.length == 2 && "Bearer".equalsIgnoreCase(parts[0])) {
                token = parts[1];
            }
        }

        if (!MessageDigest.isEqual(
                apiToken.getBytes(StandardCharsets.UTF_8),
                token.getBytes(StandardCharsets.UTF_8))) {
            response.setHeader("WWW-Authenticate", "Bearer realm=\"nanolink-demo\"");
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
            return;
        }
        filterChain.doFilter(request, response);
    }
}
