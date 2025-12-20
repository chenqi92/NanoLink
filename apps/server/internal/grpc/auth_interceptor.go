package grpc

import (
	"context"
	"strings"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

// Context keys for auth info
type contextKey string

const (
	ContextKeyUserID       contextKey = "user_id"
	ContextKeyUsername     contextKey = "username"
	ContextKeyIsSuperAdmin contextKey = "is_super_admin"
)

// AuthInterceptor handles authentication for gRPC requests
type AuthInterceptor struct {
	authService *service.AuthService
	permService *service.PermissionService
	logger      *zap.SugaredLogger
	// Methods that don't require authentication
	publicMethods map[string]bool
	// Methods that only require agent token auth (not JWT)
	agentMethods map[string]bool
}

// NewAuthInterceptor creates a new auth interceptor
func NewAuthInterceptor(
	authService *service.AuthService,
	permService *service.PermissionService,
	logger *zap.SugaredLogger,
) *AuthInterceptor {
	return &AuthInterceptor{
		authService: authService,
		permService: permService,
		logger:      logger,
		publicMethods: map[string]bool{
			"/nanolink.NanoLinkService/Authenticate": true,
			// Agent methods use token-based auth handled separately
		},
		agentMethods: map[string]bool{
			"/nanolink.NanoLinkService/Authenticate":   true,
			"/nanolink.NanoLinkService/StreamMetrics":  true,
			"/nanolink.NanoLinkService/SendHeartbeat":  true,
			"/nanolink.NanoLinkService/SendMetrics":    true,
			"/nanolink.NanoLinkService/ExecuteCommand": true,
		},
	}
}

// UnaryInterceptor returns a gRPC unary server interceptor
func (i *AuthInterceptor) UnaryInterceptor() grpc.UnaryServerInterceptor {
	return func(
		ctx context.Context,
		req interface{},
		info *grpc.UnaryServerInfo,
		handler grpc.UnaryHandler,
	) (interface{}, error) {
		// Skip auth for public methods
		if i.publicMethods[info.FullMethod] {
			return handler(ctx, req)
		}

		// Agent methods use token-based auth (handled in the method itself)
		if i.agentMethods[info.FullMethod] {
			return handler(ctx, req)
		}

		// Dashboard methods require JWT authentication
		newCtx, err := i.authorize(ctx)
		if err != nil {
			return nil, err
		}

		return handler(newCtx, req)
	}
}

// StreamInterceptor returns a gRPC stream server interceptor
func (i *AuthInterceptor) StreamInterceptor() grpc.StreamServerInterceptor {
	return func(
		srv interface{},
		stream grpc.ServerStream,
		info *grpc.StreamServerInfo,
		handler grpc.StreamHandler,
	) error {
		// Agent methods (streaming) use token-based auth
		if i.agentMethods[info.FullMethod] {
			return handler(srv, stream)
		}

		// Dashboard stream methods require JWT
		ctx := stream.Context()
		newCtx, err := i.authorize(ctx)
		if err != nil {
			return err
		}

		// Wrap stream with new context
		wrapped := &wrappedServerStream{
			ServerStream: stream,
			ctx:          newCtx,
		}

		return handler(srv, wrapped)
	}
}

// authorize verifies JWT token and returns enriched context
func (i *AuthInterceptor) authorize(ctx context.Context) (context.Context, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return nil, status.Error(codes.Unauthenticated, "metadata not provided")
	}

	// Get authorization header
	values := md.Get("authorization")
	if len(values) == 0 {
		return nil, status.Error(codes.Unauthenticated, "authorization token not provided")
	}

	// Parse Bearer token
	authHeader := values[0]
	if !strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
		return nil, status.Error(codes.Unauthenticated, "invalid authorization format")
	}

	token := strings.TrimSpace(authHeader[7:])

	// Verify JWT
	claims, err := i.authService.VerifyToken(token)
	if err != nil {
		if err == service.ErrTokenExpired {
			return nil, status.Error(codes.Unauthenticated, "token expired")
		}
		return nil, status.Error(codes.Unauthenticated, "invalid token")
	}

	// Add user info to context
	newCtx := context.WithValue(ctx, ContextKeyUserID, claims.UserID)
	newCtx = context.WithValue(newCtx, ContextKeyUsername, claims.Username)
	newCtx = context.WithValue(newCtx, ContextKeyIsSuperAdmin, claims.IsSuperAdmin)

	return newCtx, nil
}

// GetUserFromContext extracts user info from context
func GetUserFromContext(ctx context.Context) (userID uint, username string, isSuperAdmin bool, ok bool) {
	userIDVal := ctx.Value(ContextKeyUserID)
	usernameVal := ctx.Value(ContextKeyUsername)
	isSuperAdminVal := ctx.Value(ContextKeyIsSuperAdmin)

	if userIDVal == nil {
		return 0, "", false, false
	}

	userID, ok = userIDVal.(uint)
	if !ok {
		return 0, "", false, false
	}

	username, _ = usernameVal.(string)
	isSuperAdmin, _ = isSuperAdminVal.(bool)

	return userID, username, isSuperAdmin, true
}

// CheckAgentPermission checks if the user has permission for an agent
func (i *AuthInterceptor) CheckAgentPermission(ctx context.Context, agentID string, requiredLevel int) error {
	userID, _, isSuperAdmin, ok := GetUserFromContext(ctx)
	if !ok {
		return status.Error(codes.Unauthenticated, "user not authenticated")
	}

	// Super admin has full access
	if isSuperAdmin {
		return nil
	}

	// Check permission
	canExecute, err := i.permService.CanUserExecuteCommand(userID, agentID, requiredLevel)
	if err != nil {
		i.logger.Errorf("Permission check failed: %v", err)
		return status.Error(codes.Internal, "permission check failed")
	}

	if !canExecute {
		return status.Errorf(codes.PermissionDenied, "insufficient permission (required: %s)",
			database.PermissionLevelName(requiredLevel))
	}

	return nil
}

// wrappedServerStream wraps a server stream with a custom context
type wrappedServerStream struct {
	grpc.ServerStream
	ctx context.Context
}

func (w *wrappedServerStream) Context() context.Context {
	return w.ctx
}
