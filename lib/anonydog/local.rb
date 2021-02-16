require 'rugged'

github_ssh_key_path = '/tmp/ssh_key'
File.open(github_ssh_key_path, 'w') do |key_file|
  key_file << ENV['GITHUB_SSH_KEY']
end
File.open(github_ssh_key_path + '.pub', 'w') do |pubkey_file|
  pubkey_file << ENV['GITHUB_SSH_KEY_PUB']
end
ENV['GITHUB_SSH_KEY_PATH'] = github_ssh_key_path

module Anonydog
  class Local
    # Anonymizes a commit chain (head) for merging into another (base) chain.
    # Returns a Rugged::Repository where HEAD is the anonymized branch.
    #
    # Params:
    # :head => {
    #   :clone_url => URL for the repo containing the head commit,
    #   :commit => SHA-1 identifier for the head commit}
    #
    # :base => {
    #   :clone_url => URL for the repo containing the base commit,
    #   :commit => SHA-1 identifier for the base commit}
    #
    # :anonymized_branch => what should we call the anonymized branch (usually
    #   something like "pullrequest-8e457310")
    def self.anonymize(opts)
      head_repo_clone_url = opts[:head][:clone_url]
      head_commit = opts[:head][:commit]

      base_repo_clone_url = opts[:base][:clone_url]
      base_ref = "upstream/#{opts[:base][:ref]}"

      branch_name = opts[:anonymized_branch]

      repo_path = "/tmp/#{SecureRandom.hex}"

      repo = Rugged::Repository.clone_at(
        head_repo_clone_url,
        repo_path,
        bare: true)

      repo.remotes.create('upstream', base_repo_clone_url)
      repo.fetch('upstream')

      new_head = merge_base = repo.merge_base(head_commit, base_ref)

      Rugged::Walker.walk(
        repo,
        :sort => Rugged::SORT_TOPO | Rugged::SORT_REVERSE, # parents first
        :show => head_commit,
        :hide => merge_base) {
        |commit|
          fake_author_sig = {
            :name => 'Anonydog',
            :email => 'me@anonydog.org',
            :time => commit.author[:time]
          }

          current = Rugged::Commit.create(
            repo,
            :message => commit.message,
            :tree => commit.tree,
            # TODO: check for unintended side-effects here
            :committer => fake_author_sig,
            #TODO: inside a PR, can a commit have more than one parent?
            :parents => [new_head],
            :author => fake_author_sig
          )

          new_head = current
      }

      repo.branches.create(branch_name, new_head)
      repo.head = "refs/heads/#{branch_name}"
      repo
    end

    # Publishes HEAD ref/branch from a rugged repository to a remote (github)
    # repo.
    def self.publish(local_repo, remote_repo_url)
      creds = Rugged::Credentials::SshKey.new(
        publickey: File.expand_path("#{ENV['GITHUB_SSH_KEY_PATH']}.pub"),
        privatekey: File.expand_path("#{ENV['GITHUB_SSH_KEY_PATH']}"),
        username: 'git')

      # see @nulltoken's response to @timmixture at https://github.com/libgit2/libgit2sharp/issues/104#issuecomment-26504318
      force_push_ref = '+' + local_repo.head.name
      remote = local_repo.remotes.create_anonymous(remote_repo_url)
      remote.push([force_push_ref], {credentials: creds})
    end

    # Publishes anonymized branch to given URL. Returns randomly generated name
    # for the anonymized ref (can be used to open the PR)
    def self.publish_anonymized(
      base_clone_url, base_ref,
      head_clone_url, head_commit,
      publish_url, anonbranch_name
    )

      anonrepo = Anonydog::Local.anonymize(
        base: { clone_url: base_clone_url, ref: base_ref },
        head: { clone_url: head_clone_url, commit: head_commit },
        anonymized_branch: anonbranch_name
      )

      Anonydog::Local.publish(anonrepo, publish_url)

      #TODO: should we use an in-memory repo?
      puts "deleting #{anonrepo.path}"
      FileUtils.rm_rf(anonrepo.path)

      anonbranch_name
    end

    # Publishes anonymized branch to given URL. Returns randomly generated name
    # for the anonymized ref (can be used to open the PR)
    # TODO: this looks very similar to publish_anonymized. can we DRY it out?
    def self.publish_anonymized_sync(
      base_clone_url, base_ref,
      head_clone_url, head_commit,
      publish_url, anonbranch_name
    )

      anonrepo = Anonydog::Local.anonymize(
        base: { clone_url: base_clone_url, ref: base_ref },
        head: { clone_url: head_clone_url, commit: head_commit },
        anonymized_branch: anonbranch_name
      )

      Anonydog::Local.publish(anonrepo, publish_url)

      #TODO: should we use an in-memory repo?
      puts "deleting #{anonrepo.path}"
      FileUtils.rm_rf(anonrepo.path)

      anonbranch_name
    end
  end
end
