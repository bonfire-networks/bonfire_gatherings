# # SPDX-License-Identifier: AGPL-3.0-only
# defmodule Bonfire.Gathering.Gathering do
#   use Pointers.Pointable,
#     otp_app: :bonfire_gathering,
#     source: "category",
#     table_id: "2AGSCANBECATEG0RY0RHASHTAG"

#   import Flexto
#   import Untangle

#   @behaviour Bonfire.Common.SchemaModule
#   def context_module, do: Bonfire.Gathering.Gatherings
#   def query_module, do: Bonfire.Gathering.Queries

#   def follow_filters, do: [:default]

#   @user Application.compile_env!(:bonfire, :user_schema)

#   alias Ecto.Changeset
#   alias Bonfire.Gathering.Gathering
#   alias Bonfire.Classify.Tree
#   alias Bonfire.Common.Utils
#   alias Pointers.Changesets

#   @type t :: %__MODULE__{}
#   @cast ~w(id type)a

#   pointable_schema do
#     # of course, category can usually be used as a tag
#     has_one(:tag, Pointers.Pointer, foreign_key: :id)

#     field(:name, :string, virtual: true)
#     field(:summary, :string, virtual: true)
#     field(:canonical_url, :string, virtual: true)
#     field(:username, :string, virtual: true)

#     field(:begins_on, :utc_datetime_usec)
#     field(:ends_on, :utc_datetime_usec)

#     field(:status, :boolean, virtual: true)
#     field(:draft, :boolean)

#     field(:is_public, :boolean, virtual: true)
#     field(:is_disabled, :boolean, virtual: true, default: false)

#     # TODO: remove if unused
#     field(:published_at, :utc_datetime_usec)
#     field(:disabled_at, :utc_datetime_usec)
#     field(:deleted_at, :utc_datetime_usec)

#   end

#   def create_changeset(creator, attrs, is_local? \\ true)

#   def create_changeset(nil, attrs, is_local?) do
#     %Category{}
#     |> Changesets.cast(attrs, @cast)
#     |> Changeset.change(
#       id: Utils.e(attrs, :id, nil) || Pointers.ULID.generate(),
#       is_public: true
#     )
#     |> common_changeset(attrs, is_local?)
#   end

#   def create_changeset(creator, attrs, is_local?) do
#     create_changeset(nil, attrs, is_local?)
#     |> Changesets.put_assoc(:created, %{creator_id: Map.get(creator, :id, nil)})
#     |> Tree.put_tree(attrs[:custodian] || creator, attrs[:parent_category])
#     |> debug("cswithtree")
#   end

#   defp parent_category(%{parent_category: id}) when is_binary(id) do
#     id
#   end

#   defp parent_category(%{parent_category: %{id: id}}) when is_binary(id) do
#     id
#   end

#   defp parent_category(_) do
#     nil
#   end

#   defp also_known_as(%{also_known_as: also_known_as})
#        when is_binary(also_known_as) do
#     also_known_as
#   end

#   defp also_known_as(%{also_known_as: %{id: id}}) when is_binary(id) do
#     id
#   end

#   defp also_known_as(_) do
#     nil
#   end

#   def update_changeset(
#         %Category{} = category,
#         attrs
#       ) do
#     # add the mixin IDs for update
#     attrs =
#       Map.merge(attrs, %{profile: %{id: category.id}}, fn _, a, b ->
#         Map.merge(a, b)
#       end)

#     # |> Map.merge(%{character: %{id: category.id}}, fn _, a, b -> Map.merge(a, b) end)

#     category
#     |> Changesets.cast(attrs, @cast)
#     |> common_changeset(attrs)
#   end

#   defp common_changeset(changeset, attrs, is_local? \\ true)

#   defp common_changeset(changeset, attrs, is_local? = true) do
#     changeset
#     |> Changesets.cast_assoc(:character,
#       with: &Bonfire.Me.Characters.changeset/2
#     )
#     |> more_common_changeset(attrs)
#   end

#   defp common_changeset(changeset, attrs, is_local? = false) do
#     changeset
#     |> Changesets.cast_assoc(:character,
#       required: true,
#       with: &Bonfire.Me.Characters.remote_changeset/2
#     )
#     |> more_common_changeset(attrs)
#   end

#   defp more_common_changeset(changeset, attrs) do
#     changeset
#     # |> Changeset.change(
#     #  # parent_category_id: parent_category(attrs),
#     #  also_known_as_id: also_known_as(attrs)
#     # )
#     |> Changesets.cast_assoc(:profile, with: &Bonfire.Me.Profiles.changeset/2)

#     # |> Changeset.foreign_key_constraint(:pointer_id, name: :category_pointer_id_fkey)
#     # |> change_public()
#     # |> change_disabled()
#   end
# end
