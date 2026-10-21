# Vendor RAID modules

`storcli.sh` handles Broadcom/LSI StorCLI and Dell PERC CLI using read-only `/call show` and `/call/vall show` queries. `ssacli.sh` handles HPE Smart Array using read-only `ctrl all show status` and `ctrl all show config` queries. The generic `raid.sh` dispatches only installed tools and also reads Linux md arrays. Each module prints raw evidence and a verdict. Other vendors and controller firmware output variants still need separate validation. The generic check must not guess member-drive health from a logical disk's SMART output.
