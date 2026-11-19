-- Only populate missing photos; keep any photo already uploaded by restaurant.
update public.products set image_url='/images/menu/'||slug||'.webp'
where nullif(image_url,'') is null and slug in ('nasi-timbel-komplit','ayam-asam-manis-nasi','sapi-lada-hitam-nasi','nasi-timbel-gepuk','sop-iga-nasi','sei-sapi-sambal-matah','yamien-asin','yamien-manis-rica','chicken-cordon-bleu','spaghetti-carbonara','ribeye-meltique-200-gr','tenderloin-meltique-200-gr','pisang-goreng','tempe-mendoan','combo-beef-burger','vanilla-milkshake','choco-milkshake','strawberry-milkshake');
