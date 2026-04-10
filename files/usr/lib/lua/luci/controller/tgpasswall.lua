module("luci.controller.tgpasswall", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/tgpasswall") then
		return
	end

	entry({"admin", "services", "tgpasswall"}, cbi("tgpasswall/main"), _("jdc-TGbot"), 90).dependent = true
end
