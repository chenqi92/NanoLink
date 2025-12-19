package io.nanolink.sdk;

/**
 * Configuration for NanoLink Server
 */
public class NanoLinkConfig {
    private int port = 9100;
    private String tlsCertPath;
    private String tlsKeyPath;
    private boolean dashboardEnabled = true;
    private String dashboardPath = null; // null means use embedded dashboard
    private TokenValidator tokenValidator = token -> new TokenValidator.ValidationResult(true, 0);

    public int getPort() {
        return port;
    }

    public void setPort(int port) {
        this.port = port;
    }

    public String getTlsCertPath() {
        return tlsCertPath;
    }

    public void setTlsCertPath(String tlsCertPath) {
        this.tlsCertPath = tlsCertPath;
    }

    public String getTlsKeyPath() {
        return tlsKeyPath;
    }

    public void setTlsKeyPath(String tlsKeyPath) {
        this.tlsKeyPath = tlsKeyPath;
    }

    public boolean isDashboardEnabled() {
        return dashboardEnabled;
    }

    public void setDashboardEnabled(boolean dashboardEnabled) {
        this.dashboardEnabled = dashboardEnabled;
    }

    public String getDashboardPath() {
        return dashboardPath;
    }

    public void setDashboardPath(String dashboardPath) {
        this.dashboardPath = dashboardPath;
    }

    public TokenValidator getTokenValidator() {
        return tokenValidator;
    }

    public void setTokenValidator(TokenValidator tokenValidator) {
        this.tokenValidator = tokenValidator;
    }
}
