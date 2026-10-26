# Challenges Caïssa Bordeaux

Mini-app du club : le coach pose une position et propose des coups, les joueurs répondent depuis le lien WhatsApp, puis la correction (vidéo filmée depuis le téléphone) est publiée avec le classement.

- Site : https://ladoumaille.github.io/caissa-exos/
- Données : Supabase, projet `caissa-exos` (tables `members`, `exercises`, `solutions`, `answers`, bucket `videos`)
- Le lien coach n'est pas dans ce dépôt (clé dans la table `config` de Supabase).
- `supabase.sql` : schéma complet, réexécutable.
- `.github/workflows/keepalive.yml` : empêche la mise en veille de Supabase gratuit.

Charte : couleurs et logo de caissa-bordeaux.fr ; titres en Outfit, texte en Poppins (Google Fonts).
