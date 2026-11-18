using GLib.Intl;

/* resource_list.vala — the "Virtual Machines" group: one ResourceCard per Resource,
 * kept in the same order as the window's resources array, plus search filtering.
 * Owns card lifetime: remove() detaches a card from its model (MODEL-01). */
namespace Rigs {
    public class ResourceList : Adw.PreferencesGroup {
        private HashTable<string, ResourceCard> cards = new HashTable<string, ResourceCard>(str_hash, str_equal);
        private Adw.ActionRow no_results_row;

        construct {
            this.title = _("Virtual Machines");
            this.description = _("Status, resource consumption and controls");
            no_results_row = new Adw.ActionRow();
            no_results_row.title = _("No matching virtual machines found");
            no_results_row.add_prefix(new Gtk.Image.from_icon_name("system-search-symbolic"));
            no_results_row.visible = false;
            this.add(no_results_row);
        }

        // The caller connects the card's *_requested signals.
        public ResourceCard add_card(Resource resource, bool? expanded = null) {
            var card = new ResourceCard(resource);
            if (expanded != null) card.expanded = expanded;
            this.add(card);
            cards.insert(resource.id, card);
            return card;
        }

        public void remove_card(string id) {
            ResourceCard? card = cards.lookup(id);
            if (card == null) return;
            card.detach();
            this.remove(card);
            cards.remove(id);
        }

        // PreferencesGroup can only append: re-append cards so the UI follows `resources` order.
        public void reorder(GenericArray<Resource> resources) {
            for (int i = 0; i < resources.length; i++) {
                ResourceCard? card = cards.lookup(resources[i].id);
                if (card == null) continue;
                this.remove(card);
                this.add(card);
            }
        }

        public void filter(string query) {
            string q = query.strip().down();
            int matches = 0;
            cards.foreach((id, card) => {
                var r = card.resource;
                bool match = q.length == 0 || r.name.down().contains(q) || r.subtitle.down().contains(q) ||
                    r.details.down().contains(q) || r.kind.to_id().contains(q);
                card.visible = match;
                if (match) matches++;
            });
            no_results_row.visible = q.length > 0 && matches == 0;
        }

        public void focus_card(string id) {
            ResourceCard? card = cards.lookup(id);
            if (card == null) return;
            card.visible = true;
            card.expanded = true;
            card.grab_focus();
        }

        public void update_statuses(HashTable<string, ResourceStatus?> statuses) {
            statuses.foreach((id, status) => {
                ResourceCard? card = cards.lookup(id);
                if (card != null && status != null) card.update_status(status);
            });
        }

        public void collect_expanded(HashTable<string, bool> into) {
            into.remove_all();
            cards.foreach((id, card) => { into.insert(id, card.expanded); });
        }
    }
}
