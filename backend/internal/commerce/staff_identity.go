package commerce

import "net/http"

func (a *API) staffMe(w http.ResponseWriter, r *http.Request) {
	id, err := a.staff(r)
	if err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	var data []byte
	err = a.DB.QueryRow(r.Context(), `select jsonb_build_object('id',id,'full_name',full_name,'role',role,'session_version',session_version,'staff_status',staff_status) from public.profiles where id=$1`, id).Scan(&data)
	if err != nil {
		dbError(w, err)
		return
	}
	_, _ = w.Write(data)
}
