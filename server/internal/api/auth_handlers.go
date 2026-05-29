package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"workout-tracker/server/internal/auth"
)

// UserFinder looks up users for login.
type UserFinder interface {
	FindByEmail(ctx context.Context, email string) (*auth.User, error)
}

// RefreshManager issues, rotates, and revokes refresh tokens.
type RefreshManager interface {
	Issue(ctx context.Context, userID string) (string, error)
	Rotate(ctx context.Context, presented string) (userID, newToken string, err error)
	RevokeFamily(ctx context.Context, presented string) error
}

// AuthConfig wires the dependencies of AuthHandler.
type AuthConfig struct {
	Users             UserFinder
	Refresh           RefreshManager
	Signer            *auth.Signer
	APIAudience       string
	PowerSyncAudience string
	PowerSyncURL      string
	AccessTTL         time.Duration
	PowerSyncTTL      time.Duration
}

// AuthHandler serves the /auth/* endpoints.
type AuthHandler struct {
	cfg AuthConfig
}

func NewAuthHandler(cfg AuthConfig) *AuthHandler {
	return &AuthHandler{cfg: cfg}
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	RefreshToken string `json:"refresh_token"`
}

// Login verifies credentials and returns an access JWT plus a refresh token.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Email == "" || req.Password == "" {
		writeJSONError(w, http.StatusBadRequest, "email and password are required")
		return
	}

	user, err := h.cfg.Users.FindByEmail(r.Context(), req.Email)
	if err != nil {
		// Same response for unknown user and wrong password (no enumeration).
		writeJSONError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	ok, err := auth.VerifyPassword(req.Password, user.PasswordHash)
	if err != nil || !ok {
		writeJSONError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	h.issueTokens(w, r, user.ID)
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// Refresh rotates the refresh token and returns a fresh access token.
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		writeJSONError(w, http.StatusBadRequest, "refresh_token is required")
		return
	}
	userID, newRefresh, err := h.cfg.Refresh.Rotate(r.Context(), req.RefreshToken)
	if err != nil {
		writeJSONError(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}
	access, err := h.cfg.Signer.Sign(userID, h.cfg.APIAudience, h.cfg.AccessTTL)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not mint token")
		return
	}
	writeJSON(w, http.StatusOK, tokenResponse{
		AccessToken:  access,
		TokenType:    "Bearer",
		ExpiresIn:    int(h.cfg.AccessTTL.Seconds()),
		RefreshToken: newRefresh,
	})
}

// Logout revokes the refresh token's family. Idempotent.
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		writeJSONError(w, http.StatusBadRequest, "refresh_token is required")
		return
	}
	if err := h.cfg.Refresh.RevokeFamily(r.Context(), req.RefreshToken); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not revoke token")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *AuthHandler) issueTokens(w http.ResponseWriter, r *http.Request, userID string) {
	access, err := h.cfg.Signer.Sign(userID, h.cfg.APIAudience, h.cfg.AccessTTL)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not mint token")
		return
	}
	refresh, err := h.cfg.Refresh.Issue(r.Context(), userID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not issue refresh token")
		return
	}
	writeJSON(w, http.StatusOK, tokenResponse{
		AccessToken:  access,
		TokenType:    "Bearer",
		ExpiresIn:    int(h.cfg.AccessTTL.Seconds()),
		RefreshToken: refresh,
	})
}

type powerSyncTokenResponse struct {
	Endpoint  string `json:"endpoint"`
	Token     string `json:"token"`
	ExpiresAt int64  `json:"expires_at"` // unix seconds; debug aid only
}

// PowerSyncToken mints a short-lived PowerSync JWT for the authenticated user.
// It must be registered behind RequireAuth so UserIDFromContext is populated.
func (h *AuthHandler) PowerSyncToken(w http.ResponseWriter, r *http.Request) {
	userID, ok := UserIDFromContext(r.Context())
	if !ok || userID == "" {
		writeJSONError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	token, err := h.cfg.Signer.Sign(userID, h.cfg.PowerSyncAudience, h.cfg.PowerSyncTTL)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not mint powersync token")
		return
	}
	writeJSON(w, http.StatusOK, powerSyncTokenResponse{
		Endpoint:  h.cfg.PowerSyncURL,
		Token:     token,
		ExpiresAt: time.Now().Add(h.cfg.PowerSyncTTL).Unix(),
	})
}
