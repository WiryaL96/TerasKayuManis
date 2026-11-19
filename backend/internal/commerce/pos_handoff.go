package commerce

import "net/http"

// These actions record manual handoff to the external POS. They never create a
// local payment or claim that the POS was contacted by an integration.
func (a *API) posHandoff(w http.ResponseWriter, r *http.Request) {
	actor, err := a.staff(r)
	if err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	var p struct {
		ExpectedVersion int    `json:"expected_version"`
		Reference       string `json:"pos_reference"`
		TakeoverReason  string `json:"takeover_reason"`
		EnteredInPOS    bool   `json:"entered_in_pos"`
		PaidInPOS       bool   `json:"paid_in_pos"`
	}
	if !decode(w, r, &p) {
		return
	}
	version := staffSessionVersion(r.Header.Get("Authorization"))
	var raw []byte
	if r.PathValue("action") == "claim-pos" {
		if p.Reference != "" {
			writeError(w, 400, "Invalid claim")
			return
		}
		err = a.DB.QueryRow(r.Context(), "select tkm.claim_pos_order($1,$2,$3,$4,$5)", r.PathValue("id"), actor, p.ExpectedVersion, version, p.TakeoverReason).Scan(&raw)
	} else if r.PathValue("action") == "forward-pos" {
		if p.TakeoverReason != "" || !p.EnteredInPOS || !p.PaidInPOS {
			writeError(w, 400, "Invalid handoff")
			return
		}
		err = a.DB.QueryRow(r.Context(), "select tkm.forward_pos_order($1,$2,$3,$4,$5)", r.PathValue("id"), actor, p.ExpectedVersion, version, p.Reference).Scan(&raw)
	} else {
		writeError(w, 404, "Action not found")
		return
	}
	if err != nil {
		dbError(w, err)
		return
	}
	writeOrderResult(w, raw)
}
